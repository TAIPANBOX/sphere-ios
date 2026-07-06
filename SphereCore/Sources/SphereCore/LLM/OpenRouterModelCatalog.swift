import Foundation

/// One model OpenRouter can route to, trimmed to what the picker UI needs.
public struct CloudModelInfo: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let contextTokens: Int?
    /// USD per 1M tokens (OpenRouter quotes per-token strings; nil when the
    /// API omits or can't be parsed as a price).
    public let promptPricePerMTok: Double?
    public let completionPricePerMTok: Double?
    public let supportsImages: Bool

    public init(
        id: String,
        name: String,
        contextTokens: Int?,
        promptPricePerMTok: Double?,
        completionPricePerMTok: Double?,
        supportsImages: Bool
    ) {
        self.id = id
        self.name = name
        self.contextTokens = contextTokens
        self.promptPricePerMTok = promptPricePerMTok
        self.completionPricePerMTok = completionPricePerMTok
        self.supportsImages = supportsImages
    }
}

/// Fetches, caches, and curates the list of models OpenRouter can route to.
///
/// Load order: fresh disk cache → network (refreshing the cache on success)
/// → stale disk cache (any age, better than nothing) → built-in fallback.
/// An actor because the disk cache is mutated from whichever task calls
/// `load()`, and UI reads it via `await` from the main actor.
public actor OpenRouterModelCatalog {
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/models")!
    private static let cacheTTL: TimeInterval = 24 * 60 * 60

    /// Curated shortlist shown above the searchable full list, in this order.
    /// Free-tier ids (suffixed ":free") are appended when present in the
    /// fetched/cached list so the recommendation reflects real availability.
    private static let recommendedIDs = [
        "anthropic/claude-haiku-4.5",
        "openai/gpt-5-mini",
        "google/gemini-2.5-flash",
    ]

    /// Small built-in list used only when network AND cache both fail —
    /// keeps the picker usable offline on first launch.
    public static let fallback: [CloudModelInfo] = [
        CloudModelInfo(
            id: "anthropic/claude-haiku-4.5", name: "Claude Haiku 4.5",
            contextTokens: 200_000, promptPricePerMTok: 1.0, completionPricePerMTok: 5.0,
            supportsImages: true
        ),
        CloudModelInfo(
            id: "openai/gpt-5-mini", name: "GPT-5 Mini",
            contextTokens: 400_000, promptPricePerMTok: 0.25, completionPricePerMTok: 2.0,
            supportsImages: true
        ),
        CloudModelInfo(
            id: "google/gemini-2.5-flash", name: "Gemini 2.5 Flash",
            contextTokens: 1_000_000, promptPricePerMTok: 0.3, completionPricePerMTok: 2.5,
            supportsImages: true
        ),
    ]

    private let transport: any LLMTransport
    private let cacheDirectory: URL
    private let now: @Sendable () -> Date

    public init(
        transport: any LLMTransport = URLSessionTransport(),
        cacheDirectory: URL,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.cacheDirectory = cacheDirectory
        self.now = now
    }

    private var cacheFileURL: URL {
        cacheDirectory.appendingPathComponent("openrouter-models.json")
    }

    /// Returns the full model list, refreshing from the network when the
    /// cache is missing or stale. Never throws: a network failure with no
    /// usable cache falls back to the built-in list.
    public func load() async -> [CloudModelInfo] {
        if let cached = readCache(), !isStale(cached.fetchedAt) {
            return cached.models
        }
        if let fetched = try? await fetchFromNetwork() {
            writeCache(CachedCatalog(fetchedAt: now(), models: fetched))
            return fetched
        }
        if let cached = readCache() {
            return cached.models
        }
        return Self.fallback
    }

    /// Picks the curated shortlist out of `models`, preserving
    /// `recommendedIDs` order and appending up to two ":free" ids found in
    /// the fetched list (stable order as returned by the API).
    public static func recommended(from models: [CloudModelInfo]) -> [CloudModelInfo] {
        var result: [CloudModelInfo] = []
        for id in recommendedIDs {
            if let match = models.first(where: { $0.id == id }) {
                result.append(match)
            }
        }
        let freeModels = models.filter { $0.id.hasSuffix(":free") && !result.contains($0) }
        result.append(contentsOf: freeModels.prefix(2))
        return result
    }

    // MARK: - Network

    private func fetchFromNetwork() async throws -> [CloudModelInfo] {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        let (status, body) = try await transport.post(request)
        guard (200..<300).contains(status) else {
            throw LLMError.api(LLMHTTP.errorMessage(status: status, body: body))
        }
        guard let json = JSONValue.decoded(from: body), let data = json["data"]?.arrayValue else {
            throw LLMError.api("Malformed OpenRouter models response")
        }
        return data.compactMap(Self.parse)
    }

    /// Parses one raw model entry, returning nil (rather than throwing) for
    /// anything unparseable so a single bad entry never drops the whole list.
    /// Keeps only text-output models: `architecture.output_modalities`
    /// absent, or present and containing "text".
    static func parse(_ raw: JSONValue) -> CloudModelInfo? {
        guard let id = raw["id"]?.stringValue else { return nil }
        let name = raw["name"]?.stringValue ?? id

        if let outputModalities = raw["architecture"]?["output_modalities"]?.arrayValue {
            let texts = outputModalities.compactMap(\.stringValue)
            guard texts.contains("text") else { return nil }
        }

        let contextTokens = raw["context_length"]?.intValue

        let promptPrice = pricePerMTok(raw["pricing"]?["prompt"]?.stringValue)
        let completionPrice = pricePerMTok(raw["pricing"]?["completion"]?.stringValue)

        let inputModalities = raw["architecture"]?["input_modalities"]?.arrayValue?
            .compactMap(\.stringValue) ?? []
        let supportsImages = inputModalities.contains("image")

        return CloudModelInfo(
            id: id, name: name, contextTokens: contextTokens,
            promptPricePerMTok: promptPrice, completionPricePerMTok: completionPrice,
            supportsImages: supportsImages
        )
    }

    /// OpenRouter quotes `pricing.prompt`/`pricing.completion` as decimal
    /// strings in USD per token (e.g. "0.0000008"); converts to USD per 1M
    /// tokens, tolerating missing or non-numeric values as nil.
    private static func pricePerMTok(_ raw: String?) -> Double? {
        guard let raw, let perToken = Double(raw) else { return nil }
        return perToken * 1_000_000
    }

    // MARK: - Disk cache

    private struct CachedCatalog: Codable {
        let fetchedAt: Date
        let models: [CloudModelInfo]
    }

    private func isStale(_ fetchedAt: Date) -> Bool {
        now().timeIntervalSince(fetchedAt) > Self.cacheTTL
    }

    private func readCache() -> CachedCatalog? {
        guard let data = try? Data(contentsOf: cacheFileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedCatalog.self, from: data)
    }

    private func writeCache(_ catalog: CachedCatalog) {
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(catalog) else { return }
        try? data.write(to: cacheFileURL, options: .atomic)
    }
}

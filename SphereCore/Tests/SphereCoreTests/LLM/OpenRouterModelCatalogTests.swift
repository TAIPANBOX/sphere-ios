import Foundation
import Testing
@testable import SphereCore

/// Mutable "current time" box shared with a catalog's `now` closure across
/// `await` boundaries; a plain `var` can't be captured in a `@Sendable`
/// closure (see HANDOFF.md — shared mutable test doubles use a lock).
final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _date: Date

    init(_ date: Date) { _date = date }

    var date: Date {
        get { lock.withLock { _date } }
        set { lock.withLock { _date = newValue } }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { _date = _date.addingTimeInterval(seconds) }
    }
}

@Suite("OpenRouterModelCatalog")
struct OpenRouterModelCatalogTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("orcatalog-\(UUID().uuidString)", isDirectory: true)
    }

    private let sampleJSON = """
    {
      "data": [
        {
          "id": "anthropic/claude-haiku-4.5",
          "name": "Claude Haiku 4.5",
          "context_length": 200000,
          "pricing": {"prompt": "0.000001", "completion": "0.000005"},
          "architecture": {"input_modalities": ["text", "image"], "output_modalities": ["text"]}
        },
        {
          "id": "openai/gpt-5-mini",
          "name": "GPT-5 Mini",
          "context_length": 400000,
          "pricing": {"prompt": "0.00000025", "completion": "0.000002"},
          "architecture": {"input_modalities": ["text"], "output_modalities": ["text"]}
        },
        {
          "id": "some/free-model:free",
          "name": "Free Model",
          "context_length": 32000,
          "pricing": {"prompt": "0", "completion": "0"},
          "architecture": {"input_modalities": ["text"], "output_modalities": ["text"]}
        }
      ]
    }
    """

    @Test func parsesStringPricesAndImageModality() async throws {
        let transport = StubTransport(body: sampleJSON)
        let catalog = OpenRouterModelCatalog(transport: transport, cacheDirectory: tempDir())
        let models = await catalog.load()

        #expect(models.count == 3)
        let claude = try #require(models.first { $0.id == "anthropic/claude-haiku-4.5" })
        #expect(claude.name == "Claude Haiku 4.5")
        #expect(claude.contextTokens == 200_000)
        #expect(claude.promptPricePerMTok == 1.0)
        #expect(claude.completionPricePerMTok == 5.0)
        #expect(claude.supportsImages == true)

        let gpt = try #require(models.first { $0.id == "openai/gpt-5-mini" })
        #expect(gpt.supportsImages == false)
        #expect(gpt.promptPricePerMTok == 0.25)
        #expect(gpt.completionPricePerMTok == 2.0)
    }

    @Test func malformedEntriesAreIgnoredNotFatal() throws {
        // Missing id -> dropped.
        #expect(OpenRouterModelCatalog.parse(.object(["name": "No id"])) == nil)

        // Non-numeric price -> nil prices, entry still kept.
        let raw: JSONValue = .object([
            "id": "vendor/weird-price",
            "name": "Weird Price",
            "pricing": .object(["prompt": "not-a-number", "completion": "also-bad"]),
        ])
        let parsed = try #require(OpenRouterModelCatalog.parse(raw))
        #expect(parsed.promptPricePerMTok == nil)
        #expect(parsed.completionPricePerMTok == nil)
        #expect(parsed.supportsImages == false)

        // Image-only output modality -> filtered out entirely.
        let imageOnly: JSONValue = .object([
            "id": "vendor/image-only",
            "architecture": .object(["output_modalities": .array(["image"])]),
        ])
        #expect(OpenRouterModelCatalog.parse(imageOnly) == nil)

        // No architecture at all -> defaults to text-output, kept.
        let noArchitecture: JSONValue = .object(["id": "vendor/bare"])
        #expect(OpenRouterModelCatalog.parse(noArchitecture) != nil)
    }

    @Test func ignoresUnparseableEntriesWithoutFailingWholeList() async throws {
        let json = """
        {"data": [
          {"name": "No id, dropped"},
          {"id": "vendor/kept", "name": "Kept", "architecture": {"output_modalities": ["text"]}}
        ]}
        """
        let transport = StubTransport(body: json)
        let catalog = OpenRouterModelCatalog(transport: transport, cacheDirectory: tempDir())
        let models = await catalog.load()
        #expect(models.count == 1)
        #expect(models[0].id == "vendor/kept")
    }

    @Test func freshCacheIsUsedWithoutHittingNetwork() async throws {
        let dir = tempDir()
        let transport = StubTransport(body: sampleJSON)

        let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
        let catalog = OpenRouterModelCatalog(
            transport: transport, cacheDirectory: dir, now: { clock.date }
        )
        _ = await catalog.load()
        #expect(transport.requests.count == 1)

        // Advance by 1 hour (< 24h TTL): should serve from cache, no new request.
        clock.advance(by: 60 * 60)
        _ = await catalog.load()
        #expect(transport.requests.count == 1)
    }

    @Test func staleCacheTriggersRefetch() async throws {
        let dir = tempDir()
        let transport = StubTransport(body: sampleJSON)

        let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
        let catalog = OpenRouterModelCatalog(
            transport: transport, cacheDirectory: dir, now: { clock.date }
        )
        _ = await catalog.load()
        #expect(transport.requests.count == 1)

        // Advance past the 24h TTL: should refetch.
        clock.advance(by: 25 * 60 * 60)
        _ = await catalog.load()
        #expect(transport.requests.count == 2)
    }

    @Test func staleCacheServedWhenNetworkFails() async throws {
        let dir = tempDir()
        let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))

        let goodTransport = StubTransport(body: sampleJSON)
        let firstCatalog = OpenRouterModelCatalog(
            transport: goodTransport, cacheDirectory: dir, now: { clock.date }
        )
        let firstLoad = await firstCatalog.load()
        #expect(firstLoad.count == 3)

        // New catalog instance, same cache dir, network now fails, cache is stale.
        clock.advance(by: 48 * 60 * 60)
        let failingTransport = StubTransport(status: 500, body: "{\"error\":{\"message\":\"down\"}}")
        let secondCatalog = OpenRouterModelCatalog(
            transport: failingTransport, cacheDirectory: dir, now: { clock.date }
        )
        let secondLoad = await secondCatalog.load()
        // Falls back to the stale-but-present cache rather than the built-in list.
        #expect(secondLoad.count == 3)
        #expect(secondLoad.contains { $0.id == "anthropic/claude-haiku-4.5" })
    }

    @Test func fallbackUsedWhenNoNetworkAndNoCache() async throws {
        let dir = tempDir()
        let transport = StubTransport(status: 500, body: "{\"error\":{\"message\":\"down\"}}")
        let catalog = OpenRouterModelCatalog(transport: transport, cacheDirectory: dir)
        let models = await catalog.load()
        #expect(models == OpenRouterModelCatalog.fallback)
    }

    @Test func recommendedOrdersCuratedListAndAppendsFreeModels() throws {
        let models = [
            CloudModelInfo(
                id: "google/gemini-2.5-flash", name: "Gemini", contextTokens: nil,
                promptPricePerMTok: nil, completionPricePerMTok: nil, supportsImages: true
            ),
            CloudModelInfo(
                id: "vendor/a:free", name: "Free A", contextTokens: nil,
                promptPricePerMTok: nil, completionPricePerMTok: nil, supportsImages: false
            ),
            CloudModelInfo(
                id: "anthropic/claude-haiku-4.5", name: "Claude", contextTokens: nil,
                promptPricePerMTok: nil, completionPricePerMTok: nil, supportsImages: true
            ),
            CloudModelInfo(
                id: "vendor/b:free", name: "Free B", contextTokens: nil,
                promptPricePerMTok: nil, completionPricePerMTok: nil, supportsImages: false
            ),
            CloudModelInfo(
                id: "openai/gpt-5-mini", name: "GPT", contextTokens: nil,
                promptPricePerMTok: nil, completionPricePerMTok: nil, supportsImages: true
            ),
        ]

        let recommended = OpenRouterModelCatalog.recommended(from: models)
        #expect(recommended.map(\.id) == [
            "anthropic/claude-haiku-4.5",
            "openai/gpt-5-mini",
            "google/gemini-2.5-flash",
            "vendor/a:free",
            "vendor/b:free",
        ])
    }

    @Test func recommendedSkipsMissingCuratedIDsGracefully() throws {
        let models = [
            CloudModelInfo(
                id: "openai/gpt-5-mini", name: "GPT", contextTokens: nil,
                promptPricePerMTok: nil, completionPricePerMTok: nil, supportsImages: true
            ),
        ]
        let recommended = OpenRouterModelCatalog.recommended(from: models)
        #expect(recommended.map(\.id) == ["openai/gpt-5-mini"])
    }
}

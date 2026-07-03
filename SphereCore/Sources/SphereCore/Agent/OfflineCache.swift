import Foundation

public struct AgentInsight: Sendable, Equatable, Codable {
    public let insight: String
    public let tags: [String]

    public init(insight: String, tags: [String]) {
        self.insight = insight
        self.tags = tags
    }
}

/// Last-known-good LLM surfaces served when the device is offline.
public protocol OfflineCache: Sendable {
    func loadBrief() async -> String?
    func saveBrief(_ text: String) async
    func loadInsight() async -> AgentInsight?
    func saveInsight(_ insight: AgentInsight) async
}

public actor FileOfflineCache: OfflineCache {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var briefURL: URL { directory.appendingPathComponent("brief.txt") }
    private var insightURL: URL { directory.appendingPathComponent("insight.json") }

    public func loadBrief() async -> String? {
        guard let data = try? Data(contentsOf: briefURL) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func saveBrief(_ text: String) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: briefURL, options: .atomic)
    }

    public func loadInsight() async -> AgentInsight? {
        guard let data = try? Data(contentsOf: insightURL) else { return nil }
        return try? JSONDecoder().decode(AgentInsight.self, from: data)
    }

    public func saveInsight(_ insight: AgentInsight) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(insight) {
            try? data.write(to: insightURL, options: .atomic)
        }
    }
}

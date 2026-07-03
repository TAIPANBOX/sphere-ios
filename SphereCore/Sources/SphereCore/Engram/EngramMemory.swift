import Foundation

public struct EngramMemory: Sendable, Equatable, Identifiable {
    public let id: String
    public let agentId: String
    public let content: String
    public let tags: [String]
    public let salience: Double
    public let emotionalValence: Double
    public let importance: Double
    public let accessCount: Int
    public let createdAt: Date
    public let score: Double

    public init(
        id: String,
        agentId: String,
        content: String,
        tags: [String],
        salience: Double,
        emotionalValence: Double,
        importance: Double,
        accessCount: Int,
        createdAt: Date,
        score: Double
    ) {
        self.id = id
        self.agentId = agentId
        self.content = content
        self.tags = tags
        self.salience = salience
        self.emotionalValence = emotionalValence
        self.importance = importance
        self.accessCount = accessCount
        self.createdAt = createdAt
        self.score = score
    }
}

public func formatMemoriesAsContext(_ memories: [EngramMemory]) -> String {
    guard !memories.isEmpty else { return "" }
    var buffer = "<memory>\n"
    for memory in memories {
        buffer += memory.content + "\n"
    }
    buffer += "</memory>"
    return buffer
}

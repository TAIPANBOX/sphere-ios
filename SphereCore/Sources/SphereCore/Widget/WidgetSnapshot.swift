import Foundation

/// Compact home-screen/Smart-Stack snapshot the app writes and the widget
/// extension reads. Kept small and self-contained so the widget never
/// touches GRDB, HealthKit, or the network — it just renders this.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct FocusLine: Codable, Equatable, Sendable {
        public let emoji: String
        public let title: String

        public init(emoji: String, title: String) {
            self.emoji = emoji
            self.title = title
        }
    }

    public struct ShoppingLine: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    /// 0–100
    public let lifeScore: Int
    public let bestEmoji: String
    public let bestName: String
    public let needsFocusEmoji: String
    public let needsFocusName: String
    public let topFocus: [FocusLine]
    /// Open shopping items, shown and checkable on the watch.
    public let shopping: [ShoppingLine]
    /// The agent's answer to the last watch voice query, if any.
    public let agentReply: String?
    public let updatedAt: Date

    public init(
        lifeScore: Int,
        bestEmoji: String,
        bestName: String,
        needsFocusEmoji: String,
        needsFocusName: String,
        topFocus: [FocusLine],
        shopping: [ShoppingLine] = [],
        agentReply: String? = nil,
        updatedAt: Date
    ) {
        self.lifeScore = lifeScore
        self.bestEmoji = bestEmoji
        self.bestName = bestName
        self.needsFocusEmoji = needsFocusEmoji
        self.needsFocusName = needsFocusName
        self.topFocus = topFocus
        self.shopping = shopping
        self.agentReply = agentReply
        self.updatedAt = updatedAt
    }

    // Tolerant decoder: snapshots written by older builds lack `shopping` /
    // `agentReply`, so those default rather than failing the whole decode.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lifeScore = try c.decode(Int.self, forKey: .lifeScore)
        bestEmoji = try c.decode(String.self, forKey: .bestEmoji)
        bestName = try c.decode(String.self, forKey: .bestName)
        needsFocusEmoji = try c.decode(String.self, forKey: .needsFocusEmoji)
        needsFocusName = try c.decode(String.self, forKey: .needsFocusName)
        topFocus = try c.decode([FocusLine].self, forKey: .topFocus)
        shopping = try c.decodeIfPresent([ShoppingLine].self, forKey: .shopping) ?? []
        agentReply = try c.decodeIfPresent(String.self, forKey: .agentReply)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    /// Shown before the app has written a real snapshot.
    public static let placeholder = WidgetSnapshot(
        lifeScore: 72,
        bestEmoji: "💼",
        bestName: "Career",
        needsFocusEmoji: "🎯",
        needsFocusName: "Goals",
        topFocus: [
            FocusLine(emoji: "👟", title: "Reach your step goal"),
            FocusLine(emoji: "🧘", title: "Daily meditation"),
        ],
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

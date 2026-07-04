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

    /// 0–100
    public let lifeScore: Int
    public let bestEmoji: String
    public let bestName: String
    public let needsFocusEmoji: String
    public let needsFocusName: String
    public let topFocus: [FocusLine]
    public let updatedAt: Date

    public init(
        lifeScore: Int,
        bestEmoji: String,
        bestName: String,
        needsFocusEmoji: String,
        needsFocusName: String,
        topFocus: [FocusLine],
        updatedAt: Date
    ) {
        self.lifeScore = lifeScore
        self.bestEmoji = bestEmoji
        self.bestName = bestName
        self.needsFocusEmoji = needsFocusEmoji
        self.needsFocusName = needsFocusName
        self.topFocus = topFocus
        self.updatedAt = updatedAt
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

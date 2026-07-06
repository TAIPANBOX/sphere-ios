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

    /// One chip from a wrist capture: a logged fact or a failed one.
    public struct CaptureLine: Codable, Equatable, Sendable {
        public let summary: String
        public let isError: Bool

        public init(summary: String, isError: Bool) {
            self.summary = summary
            self.isError = isError
        }
    }

    /// One tappable follow-up suggestion. Tapping it on the watch re-runs the
    /// `prompt` through the capture pipeline.
    public struct SuggestionLine: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let prompt: String

        public init(id: String, title: String, prompt: String) {
            self.id = id
            self.title = title
            self.prompt = prompt
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
    /// When `agentReply` was cached; nil when there is no reply. The watch
    /// compares this to its query-submission time to know a fresh reply
    /// landed, and formats it as a relative timestamp under the reply.
    public let agentReplyAt: Date?
    /// Confirmation chips from the last wrist capture, if any. Takes
    /// precedence over `agentReply` in the watch UI when non-empty.
    public let captureResults: [CaptureLine]
    /// Tappable follow-up suggestions from the last agent capture, if any.
    public let suggestions: [SuggestionLine]
    /// Glasses of water logged today.
    public let waterToday: Int
    /// Daily water goal in glasses.
    public let waterGoal: Int
    /// Whether the user has a meditation session logged today.
    public let meditatedToday: Bool
    /// Today's mood check-in (1–5), if any.
    public let moodToday: Int?
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
        agentReplyAt: Date? = nil,
        captureResults: [CaptureLine] = [],
        suggestions: [SuggestionLine] = [],
        waterToday: Int = 0,
        waterGoal: Int = 8,
        meditatedToday: Bool = false,
        moodToday: Int? = nil,
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
        self.agentReplyAt = agentReplyAt
        self.captureResults = captureResults
        self.suggestions = suggestions
        self.waterToday = waterToday
        self.waterGoal = waterGoal
        self.meditatedToday = meditatedToday
        self.moodToday = moodToday
        self.updatedAt = updatedAt
    }

    // Tolerant decoder: snapshots written by older builds lack newer fields,
    // so those default rather than failing the whole decode.
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
        agentReplyAt = try c.decodeIfPresent(Date.self, forKey: .agentReplyAt)
        captureResults = try c.decodeIfPresent([CaptureLine].self, forKey: .captureResults) ?? []
        suggestions = try c.decodeIfPresent([SuggestionLine].self, forKey: .suggestions) ?? []
        waterToday = try c.decodeIfPresent(Int.self, forKey: .waterToday) ?? 0
        waterGoal = try c.decodeIfPresent(Int.self, forKey: .waterGoal) ?? 8
        meditatedToday = try c.decodeIfPresent(Bool.self, forKey: .meditatedToday) ?? false
        moodToday = try c.decodeIfPresent(Int.self, forKey: .moodToday)
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
        waterToday: 0,
        waterGoal: 8,
        meditatedToday: false,
        moodToday: nil,
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

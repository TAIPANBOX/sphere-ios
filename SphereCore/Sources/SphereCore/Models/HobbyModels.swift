import Foundation
import GRDB

public enum HobbyFrequency: String, Codable, CaseIterable, Sendable {
    case daily, weekly, monthly, occasionally

    public var label: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .occasionally: "Occasionally"
        }
    }
}

public struct Hobby: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    public var frequency: HobbyFrequency
    public var targetMinutesPerWeek: Int
    public var isActive: Bool
    public var goal: String
    public var equipment: [String]
    public var resources: [String]
    /// Total money spent on gear/lessons — drives the cost-per-session stat.
    public var costTotal: Double

    public init(
        id: String,
        name: String,
        emoji: String = "🎸",
        frequency: HobbyFrequency = .weekly,
        targetMinutesPerWeek: Int = 60,
        isActive: Bool = true,
        goal: String = "",
        equipment: [String] = [],
        resources: [String] = [],
        costTotal: Double = 0
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.frequency = frequency
        self.targetMinutesPerWeek = targetMinutesPerWeek
        self.isActive = isActive
        self.goal = goal
        self.equipment = equipment
        self.resources = resources
        self.costTotal = costTotal
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("hobby", now: now)
    }
}

extension Hobby: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "hobbies"
}

public struct HobbySession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var hobbyId: String
    public var durationMinutes: Int
    public var date: Date
    public var note: String
    /// 1–5 enjoyment rating (0 = not rated) — the diary/taste layer.
    public var rating: Int

    public init(
        id: String, hobbyId: String, durationMinutes: Int, date: Date,
        note: String = "", rating: Int = 0
    ) {
        self.id = id
        self.hobbyId = hobbyId
        self.durationMinutes = durationMinutes
        self.date = date
        self.note = note
        self.rating = rating
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("hsession", now: now)
    }
}

extension HobbySession: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "hobby_sessions"
}

/// A progression milestone for a hobby (beginner → advanced checklist).
public struct HobbyMilestone: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var hobbyId: String
    public var title: String
    public var done: Bool

    public init(id: String, hobbyId: String, title: String, done: Bool = false) {
        self.id = id
        self.hobbyId = hobbyId
        self.title = title
        self.done = done
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("milestone", now: now) }
}

extension HobbyMilestone: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "hobby_milestones"
}

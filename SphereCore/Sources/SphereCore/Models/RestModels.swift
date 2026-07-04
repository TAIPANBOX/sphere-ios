import Foundation
import GRDB

public enum RecoveryLevel: String, Codable, CaseIterable, Sendable {
    case poor, fair, good, excellent

    public var label: String {
        switch self {
        case .poor: "Poor"
        case .fair: "Fair"
        case .good: "Good"
        case .excellent: "Excellent"
        }
    }

    public var emoji: String {
        switch self {
        case .poor: "😴"
        case .fair: "😐"
        case .good: "🙂"
        case .excellent: "✨"
        }
    }

    public var score: Int {
        switch self {
        case .poor: 1
        case .fair: 2
        case .good: 3
        case .excellent: 4
        }
    }
}

public struct SleepEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var date: Date
    public var hoursSlept: Double
    public var recovery: RecoveryLevel
    public var note: String
    /// 0–23
    public var bedtimeHour: Int
    public var bedtimeMinute: Int

    public init(
        id: String,
        date: Date,
        hoursSlept: Double,
        recovery: RecoveryLevel = .good,
        note: String = "",
        bedtimeHour: Int = 23,
        bedtimeMinute: Int = 0
    ) {
        self.id = id
        self.date = date
        self.hoursSlept = hoursSlept
        self.recovery = recovery
        self.note = note
        self.bedtimeHour = bedtimeHour
        self.bedtimeMinute = bedtimeMinute
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("sleep", now: now)
    }
}

extension SleepEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "sleep_entries"
}

/// Single-row record (`id == "main"`).
public struct SleepSchedule: Codable, Equatable, Sendable {
    public var id: String
    public var bedtimeHour: Int
    public var bedtimeMinute: Int
    public var wakeHour: Int
    public var wakeMinute: Int
    public var goalHours: Double
    public var remindersEnabled: Bool

    public init(
        bedtimeHour: Int = 23,
        bedtimeMinute: Int = 0,
        wakeHour: Int = 7,
        wakeMinute: Int = 0,
        goalHours: Double = 8,
        remindersEnabled: Bool = false
    ) {
        self.id = "main"
        self.bedtimeHour = bedtimeHour
        self.bedtimeMinute = bedtimeMinute
        self.wakeHour = wakeHour
        self.wakeMinute = wakeMinute
        self.goalHours = goalHours
        self.remindersEnabled = remindersEnabled
    }

    public var bedtimeLabel: String {
        String(format: "%02d:%02d", bedtimeHour, bedtimeMinute)
    }

    public var wakeLabel: String {
        String(format: "%02d:%02d", wakeHour, wakeMinute)
    }

    /// Hours between bedtime and wake time, rolling over midnight.
    public var scheduledHours: Double {
        let bedMinutes = bedtimeHour * 60 + bedtimeMinute
        var wakeMinutes = wakeHour * 60 + wakeMinute
        if wakeMinutes <= bedMinutes { wakeMinutes += 24 * 60 }
        return Double(wakeMinutes - bedMinutes) / 60
    }
}

extension SleepSchedule: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "sleep_schedule"
}

public struct WeekendPlan: Codable, Equatable, Identifiable, Sendable {
    /// Monday-anchored key, e.g. "2026-W07-06".
    public var weekKey: String
    public var activities: [String]
    public var location: String
    public var withWho: String
    public var note: String

    public var id: String { weekKey }

    public init(
        weekKey: String,
        activities: [String] = [],
        location: String = "",
        withWho: String = "",
        note: String = ""
    ) {
        self.weekKey = weekKey
        self.activities = activities
        self.location = location
        self.withWho = withWho
        self.note = note
    }
}

extension WeekendPlan: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "weekend_plans"
}

// MARK: - rest-v2 (naps, recovery activities, vacation ledger)

public struct Nap: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var date: Date
    public var minutes: Int
    public var note: String

    public init(id: String, date: Date, minutes: Int, note: String = "") {
        self.id = id
        self.date = date
        self.minutes = minutes
        self.note = note
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("nap", now: now) }
}

extension Nap: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "naps"
}

/// A restorative activity with the user's own effectiveness rating — so the
/// app learns what actually recharges *you*, not a generic list.
public struct RecoveryActivity: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    /// How well it restores you, 1–5.
    public var rating: Int
    public var note: String

    public init(id: String, name: String, emoji: String = "🌿", rating: Int = 3, note: String = "") {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.rating = rating
        self.note = note
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("recovery", now: now) }
}

extension RecoveryActivity: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "recovery_activities"
}

/// Pure sleep-debt math.
public enum SleepMath {
    /// Accumulated deficit vs the nightly goal (0 on nights at/above goal).
    public static func sleepDebt(hoursByNight: [Double], goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return hoursByNight.reduce(0) { $0 + max(goal - $1, 0) }
    }
}

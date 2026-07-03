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
        "sleep_\(Int64(now.timeIntervalSince1970 * 1000))"
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

import Foundation
import GRDB

public struct Habit: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    /// Check-in days as "yyyy-MM-dd" keys in the user's current calendar.
    public var checkInDates: [String]
    /// Who this habit makes you — "a vote for who you're becoming" (Atoms).
    public var identity: String
    /// Calendar weekdays (1 = Sun … 7 = Sat) to send a reminder; empty = none.
    public var reminderWeekdays: [Int]

    public init(
        id: String, name: String, emoji: String = "✅",
        checkInDates: [String] = [], identity: String = "", reminderWeekdays: [Int] = []
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.checkInDates = checkInDates
        self.identity = identity
        self.reminderWeekdays = reminderWeekdays
    }

    /// Checked-in flags for the trailing `days` days (oldest first) — the
    /// streak heatmap.
    public func heatmap(days: Int = 28, asOf now: Date = Date()) -> [Bool] {
        (0..<days).reversed().map { daysAgo in
            checkedIn(on: now.addingTimeInterval(Double(-daysAgo) * 86_400))
        }
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("habit", now: now)
    }

    public func checkedIn(on date: Date = Date()) -> Bool {
        checkInDates.contains(Self.dateKey(date))
    }

    /// Consecutive checked-in days ending today (or yesterday when today is
    /// not yet checked in).
    public func streak(asOf now: Date = Date()) -> Int {
        guard !checkInDates.isEmpty else { return 0 }
        let dates = Set(checkInDates)
        var cursor = checkedIn(on: now) ? now : now.addingTimeInterval(-86_400)
        var count = 0
        while dates.contains(Self.dateKey(cursor)) {
            count += 1
            cursor = cursor.addingTimeInterval(-86_400)
        }
        return count
    }

    public func checkingIn(on date: Date = Date()) -> Habit {
        let key = Self.dateKey(date)
        guard !checkInDates.contains(key) else { return self }
        var copy = self
        copy.checkInDates.append(key)
        return copy
    }

    public func uncheckingIn(on date: Date = Date()) -> Habit {
        let key = Self.dateKey(date)
        var copy = self
        copy.checkInDates.removeAll { $0 == key }
        return copy
    }

    static func dateKey(_ date: Date) -> String {
        DayKey.make(date)
    }
}

extension Habit: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "habits"
}

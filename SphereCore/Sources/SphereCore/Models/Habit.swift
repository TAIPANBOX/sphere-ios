import Foundation
import GRDB

public struct Habit: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    /// Check-in days as "yyyy-MM-dd" keys in the user's current calendar.
    public var checkInDates: [String]

    public init(id: String, name: String, emoji: String = "✅", checkInDates: [String] = []) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.checkInDates = checkInDates
    }

    public static func newID(now: Date = Date()) -> String {
        "habit_\(Int64(now.timeIntervalSince1970 * 1000))"
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
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

extension Habit: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "habits"
}

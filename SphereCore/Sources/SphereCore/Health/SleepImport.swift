import Foundation

/// One raw sleep segment from a health source, kept HealthKit-free so the
/// aggregation can be unit-tested.
public struct SleepInterval: Sendable, Equatable {
    public let start: Date
    public let end: Date
    /// True for actual sleep stages (asleep / core / deep / REM); false for
    /// in-bed-but-awake, which must not inflate the total.
    public let asleep: Bool

    public init(start: Date, end: Date, asleep: Bool) {
        self.start = start
        self.end = end
        self.asleep = asleep
    }
}

/// One night's aggregated sleep: the morning-day it belongs to and hours asleep.
public struct SleepNight: Sendable, Equatable {
    public let date: Date
    public let hours: Double

    public init(date: Date, hours: Double) {
        self.date = date
        self.hours = hours
    }
}

/// Pure aggregation of raw sleep segments into per-night totals. A segment is
/// attributed to the calendar day it *ends* on (the morning you woke up), and
/// asleep durations within that day are summed. Awake-in-bed segments are
/// ignored.
public enum SleepImport {
    public static func nights(from intervals: [SleepInterval]) -> [SleepNight] {
        var secondsByDay: [String: Double] = [:]
        for interval in intervals where interval.asleep {
            let seconds = interval.end.timeIntervalSince(interval.start)
            guard seconds > 0 else { continue }
            let key = DayKey.make(interval.end)
            secondsByDay[key, default: 0] += seconds
        }
        return secondsByDay
            .compactMap { key, seconds -> SleepNight? in
                guard let date = DayKey.date(from: key) else { return nil }
                return SleepNight(date: date, hours: (seconds / 3_600))
            }
            .sorted { $0.date < $1.date }
    }
}

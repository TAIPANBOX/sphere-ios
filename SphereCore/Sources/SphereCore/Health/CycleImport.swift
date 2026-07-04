import Foundation

/// One day of menstrual flow from a health source, already mapped to the app's
/// `FlowLevel` so the grouping stays HealthKit-free.
public struct CycleFlowDay: Sendable, Equatable {
    public let date: Date
    public let flow: FlowLevel

    public init(date: Date, flow: FlowLevel) {
        self.date = date
        self.flow = flow
    }
}

/// A period grouped from consecutive flow days: first day, last day, and the
/// heaviest flow observed across it.
public struct ImportedPeriod: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let flow: FlowLevel

    public init(start: Date, end: Date, flow: FlowLevel) {
        self.start = start
        self.end = end
        self.flow = flow
    }
}

/// Pure grouping of per-day menstrual-flow samples into periods. Consecutive
/// calendar days (gap of 1 day) belong to the same period; a larger gap starts
/// a new one.
public enum CycleImport {
    private static let intensity: [FlowLevel: Int] = [.light: 0, .medium: 1, .heavy: 2]

    public static func periods(from days: [CycleFlowDay]) -> [ImportedPeriod] {
        let sorted = days.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return [] }

        var periods: [ImportedPeriod] = []
        var startDay = sorted[0]
        var endDay = sorted[0]
        var heaviest = sorted[0].flow

        func flush() {
            periods.append(ImportedPeriod(start: startDay.date, end: endDay.date, flow: heaviest))
        }

        for day in sorted.dropFirst() {
            let gap = daysBetween(endDay.date, day.date)
            if gap <= 1 {
                endDay = day
                if (intensity[day.flow] ?? 0) > (intensity[heaviest] ?? 0) { heaviest = day.flow }
            } else {
                flush()
                startDay = day
                endDay = day
                heaviest = day.flow
            }
        }
        flush()
        return periods
    }

    private static func daysBetween(_ a: Date, _ b: Date) -> Int {
        guard let ka = DayKey.date(from: DayKey.make(a)),
              let kb = DayKey.date(from: DayKey.make(b)) else { return .max }
        return Int((kb.timeIntervalSince(ka) / 86_400).rounded())
    }
}

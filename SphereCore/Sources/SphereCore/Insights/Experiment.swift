import Foundation
import GRDB

public enum ExperimentStatus: String, Codable, CaseIterable, Sendable {
    case running, completed, abandoned
}

/// A user-run N-of-1 experiment: one deliberate behaviour change measured for
/// its cross-sphere effect (Bearable's experiments, generalised).
public struct Experiment: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    /// The intervention, phrased as the user made it ("Cut caffeine after 2pm").
    public var title: String
    public var note: String
    public var startDate: Date
    public var durationDays: Int
    public var status: ExperimentStatus
    public var createdAt: Date

    public init(
        id: String, title: String, note: String = "", startDate: Date,
        durationDays: Int, status: ExperimentStatus = .running, createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.startDate = startDate
        self.durationDays = durationDays
        self.status = status
        self.createdAt = createdAt
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("experiment", now: now) }

    /// Day the experiment window ends (start + duration - 1).
    public var endDate: Date { startDate.addingTimeInterval(Double(durationDays - 1) * 86_400) }

    /// Whole days elapsed since the start (0 on day one), clamped at 0.
    public func daysElapsed(asOf now: Date = Date()) -> Int {
        guard let start = DayKey.date(from: DayKey.make(startDate)),
              let today = DayKey.date(from: DayKey.make(now)) else { return 0 }
        return max(0, Int((today.timeIntervalSince(start) / 86_400).rounded()))
    }

    /// Human day counter: "Day N of duration", 1-based and capped at duration.
    public func dayNumber(asOf now: Date = Date()) -> Int {
        min(daysElapsed(asOf: now) + 1, durationDays)
    }

    /// Days still to run after today, clamped to 0…duration.
    public func daysRemaining(asOf now: Date = Date()) -> Int {
        max(0, durationDays - dayNumber(asOf: now))
    }

    /// Complete once the final scheduled day has arrived (consistent with
    /// `daysRemaining == 0` on that day).
    public func isWindowComplete(asOf now: Date = Date()) -> Bool {
        daysElapsed(asOf: now) >= durationDays - 1
    }
}

extension Experiment: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "experiments"
}

/// The measured shift in one metric between the baseline window (the equal-length
/// stretch just before the experiment) and the experiment window itself.
public struct MetricEffect: Sendable, Equatable {
    public let metricID: String
    public let displayName: String
    public let baselineMean: Double
    public let duringMean: Double
    public let baselineN: Int
    public let duringN: Int

    public var delta: Double { duringMean - baselineMean }
    public var percentChange: Double? {
        baselineMean == 0 ? nil : (delta / abs(baselineMean)) * 100
    }
}

/// Pure N-of-1 analysis: compares each metric's experiment window against the
/// baseline window of the same length immediately before it.
public enum ExperimentEngine {
    /// Minimum logged days in each window for an effect to be trustworthy.
    public static let minPerWindow = 3
    /// Below this absolute percent change, an effect is treated as flat.
    public static let flatThresholdPercent = 5.0

    public static func analyze(
        series: [DailySeries], startKey: String, durationDays: Int, asOf now: Date = Date()
    ) -> [MetricEffect] {
        let todayKey = DayKey.make(now)
        // Experiment window: start … min(start+duration-1, today).
        let duringKeys = windowKeys(from: startKey, length: durationDays)
            .filter { $0 <= todayKey }
        // Baseline window: the `durationDays` days immediately before the start.
        guard let baselineStart = DayKey.shift(startKey, byDays: -durationDays) else { return [] }
        let baselineKeys = windowKeys(from: baselineStart, length: durationDays)

        return series.compactMap { s -> MetricEffect? in
            let baseline = baselineKeys.compactMap { s.values[$0] }
            let during = duringKeys.compactMap { s.values[$0] }
            guard baseline.count >= minPerWindow, during.count >= minPerWindow else { return nil }
            return MetricEffect(
                metricID: s.metricID, displayName: s.displayName,
                baselineMean: mean(baseline), duringMean: mean(during),
                baselineN: baseline.count, duringN: during.count
            )
        }
        .sorted { abs($0.percentChange ?? 0) > abs($1.percentChange ?? 0) }
    }

    /// A one-line verdict from the strongest effect, or nil when nothing moved.
    public static func headline(_ effects: [MetricEffect]) -> String? {
        guard let top = effects.first, let pct = top.percentChange,
              abs(pct) >= flatThresholdPercent else { return nil }
        let dir = pct > 0 ? "up" : "down"
        return "\(top.displayName) went \(dir) \(abs(Int(pct.rounded())))% during this change."
    }

    private static func windowKeys(from startKey: String, length: Int) -> [String] {
        (0..<max(0, length)).compactMap { DayKey.shift(startKey, byDays: $0) }
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

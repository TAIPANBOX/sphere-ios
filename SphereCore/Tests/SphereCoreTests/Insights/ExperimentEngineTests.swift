import Foundation
import Testing
@testable import SphereCore

@Suite("ExperimentEngine")
struct ExperimentEngineTests {
    private let cal = Calendar(identifier: .gregorian)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// Builds a series whose values run day-by-day forward from `firstKey`.
    private func series(_ id: String, from firstKey: String, _ values: [Double]) -> DailySeries {
        var dict: [String: Double] = [:]
        for (i, v) in values.enumerated() {
            if let key = DayKey.shift(firstKey, byDays: i) { dict[key] = v }
        }
        return DailySeries(metricID: id, displayName: id.capitalized, values: dict)
    }

    @Test func measuresDropBetweenBaselineAndExperiment() {
        // Baseline Jun 1-7 all = 8; experiment Jun 8-14 all = 6.
        let start = "2026-06-08"
        let baseline = series("sleep", from: "2026-06-01", Array(repeating: 8.0, count: 7))
        var merged = baseline.values
        series("sleep", from: start, Array(repeating: 6.0, count: 7)).values
            .forEach { merged[$0.key] = $0.value }
        let s = DailySeries(metricID: "sleep", displayName: "Sleep", values: merged)

        let effects = ExperimentEngine.analyze(
            series: [s], startKey: start, durationDays: 7, asOf: day(2026, 6, 14)
        )
        let sleep = effects.first { $0.metricID == "sleep" }!
        #expect(sleep.baselineMean == 8)
        #expect(sleep.duringMean == 6)
        #expect(sleep.delta == -2)
        #expect(sleep.percentChange == -25)
        #expect(sleep.baselineN == 7)
        #expect(sleep.duringN == 7)
    }

    @Test func skipsMetricsWithTooFewLoggedDays() {
        let start = "2026-06-08"
        // Only 2 baseline points → below minPerWindow.
        var values: [String: Double] = ["2026-06-01": 5, "2026-06-02": 5]
        for i in 0..<7 { values[DayKey.shift(start, byDays: i)!] = 7 }
        let s = DailySeries(metricID: "mood", displayName: "Mood", values: values)
        #expect(ExperimentEngine.analyze(series: [s], startKey: start, durationDays: 7).isEmpty)
    }

    @Test func onlyCountsExperimentDaysUpToToday() {
        // 14-day experiment but only 4 days in so far.
        let start = "2026-06-08"
        let baseline = series("energy", from: "2026-05-25", Array(repeating: 4.0, count: 14))
        var merged = baseline.values
        for i in 0..<4 { merged[DayKey.shift(start, byDays: i)!] = 9 }
        let s = DailySeries(metricID: "energy", displayName: "Energy", values: merged)

        let effects = ExperimentEngine.analyze(
            series: [s], startKey: start, durationDays: 14, asOf: day(2026, 6, 11)
        )
        let energy = effects.first { $0.metricID == "energy" }!
        #expect(energy.duringN == 4)
        #expect(energy.duringMean == 9)
    }

    @Test func sortsByStrongestPercentChange() {
        let start = "2026-06-08"
        func metric(_ id: String, base: Double, during: Double) -> DailySeries {
            var v: [String: Double] = [:]
            for i in 0..<7 { v[DayKey.shift("2026-06-01", byDays: i)!] = base }
            for i in 0..<7 { v[DayKey.shift(start, byDays: i)!] = during }
            return DailySeries(metricID: id, displayName: id.capitalized, values: v)
        }
        let small = metric("spend", base: 100, during: 105)   // +5%
        let big = metric("mood", base: 2, during: 4)          // +100%
        let effects = ExperimentEngine.analyze(
            series: [small, big], startKey: start, durationDays: 7, asOf: day(2026, 6, 14)
        )
        #expect(effects.first?.metricID == "mood")
    }

    @Test func headlineDescribesTopEffect() {
        let effects = [
            MetricEffect(metricID: "sleep", displayName: "Sleep",
                         baselineMean: 6, duringMean: 7.5, baselineN: 7, duringN: 7)
        ]
        #expect(ExperimentEngine.headline(effects)?.contains("Sleep went up 25%") == true)
    }

    @Test func headlineNilWhenEffectIsFlat() {
        let effects = [
            MetricEffect(metricID: "mood", displayName: "Mood",
                         baselineMean: 4, duringMean: 4.1, baselineN: 7, duringN: 7)
        ]
        #expect(ExperimentEngine.headline(effects) == nil)
    }

    @Test func dayCountersTrackProgress() {
        let exp = Experiment(
            id: "e1", title: "No caffeine", startDate: day(2026, 6, 8),
            durationDays: 14, createdAt: day(2026, 6, 8)
        )
        #expect(exp.dayNumber(asOf: day(2026, 6, 8)) == 1)
        #expect(exp.daysRemaining(asOf: day(2026, 6, 8)) == 13)
        #expect(exp.dayNumber(asOf: day(2026, 6, 12)) == 5)
        // Jun 21 is day 14 (the final day): 0 days remaining, so complete.
        #expect(exp.daysRemaining(asOf: day(2026, 6, 21)) == 0)
        #expect(exp.isWindowComplete(asOf: day(2026, 6, 20)) == false)  // day 13
        #expect(exp.isWindowComplete(asOf: day(2026, 6, 21)) == true)   // day 14
        #expect(exp.dayNumber(asOf: day(2026, 6, 30)) == 14)
    }
}

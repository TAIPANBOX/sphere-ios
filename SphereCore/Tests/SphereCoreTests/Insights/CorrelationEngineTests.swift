import Foundation
import Testing
@testable import SphereCore

@Suite("CorrelationEngine")
struct CorrelationEngineTests {
    @Test func pearsonPerfectPositiveAndNegative() {
        #expect(CorrelationEngine.pearson([(1, 2), (2, 4), (3, 6)])! > 0.999)
        #expect(CorrelationEngine.pearson([(1, 6), (2, 4), (3, 2)])! < -0.999)
    }

    @Test func pearsonNilForConstantSeries() {
        #expect(CorrelationEngine.pearson([(1, 5), (2, 5), (3, 5)]) == nil)
        #expect(CorrelationEngine.pearson([(5, 1)]) == nil)
    }

    private func series(_ id: String, _ pairs: [(String, Double)]) -> DailySeries {
        DailySeries(metricID: id, displayName: id.capitalized,
                    values: Dictionary(uniqueKeysWithValues: pairs))
    }

    private func days(_ base: [Double]) -> [(String, Double)] {
        base.enumerated().map { ("2026-06-\(String(format: "%02d", $0.offset + 1))", $0.element) }
    }

    @Test func findsStrongSameDayCorrelationOverThreshold() throws {
        // 12 aligned days, strongly positive.
        let a = series("workouts", days([10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120]))
        let b = series("mood", days([1, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5]))
        let found = CorrelationEngine.correlations([a, b])
        // Same-day plus both lag-1 directions all clear the threshold.
        let sameDay = try #require(found.first { $0.lagDays == 0 })
        #expect(sameDay.r > 0.3)
        #expect(sameDay.n == 12)
        #expect(sameDay.phrase.contains("tends to be higher"))
    }

    @Test func ignoresWeakOrUndersampled() {
        // Strong but only 5 overlapping days → below minOverlap.
        let a = series("a", days([1, 2, 3, 4, 5]))
        let b = series("b", days([2, 4, 6, 8, 10]))
        #expect(CorrelationEngine.correlations([a, b]).isEmpty)
    }

    @Test func detectsLaggedRelationship() {
        // b(day+1) tracks a(day): a on Jun 1..12 predicts b on Jun 2..13.
        var aPairs = days([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
        let a = series("sleep", aPairs)
        // b shifted one day forward, same ascending pattern.
        let bPairs = (1...12).map { ("2026-06-\(String(format: "%02d", $0 + 1))", Double($0)) }
        let b = series("energy", bPairs)
        let found = CorrelationEngine.correlations([a, b])
        // Same-day overlap (Jun 2..12) is also strong, but the lag-1 variant
        // exists and is reported.
        #expect(found.contains { $0.lagDays == 1 })
        _ = aPairs
    }

    @Test func dayKeyShiftAndParse() {
        #expect(DayKey.shift("2026-06-30", byDays: 1) == "2026-07-01")
        #expect(DayKey.shift("2026-01-01", byDays: -1) == "2025-12-31")
        #expect(DayKey.date(from: "bad") == nil)
    }
}

@Suite("InsightsStore assembly")
@MainActor
struct InsightsStoreTests {
    @Test func buildsSeriesAndFindsInsight() async throws {
        let db = try AppDatabase.inMemory()
        let health = HealthStore(database: db)
        let mindfulness = MindfulnessStore(database: db)
        let rest = RestStore(database: db)
        let finance = FinanceStore(database: db)
        let hobbies = HobbiesStore(database: db)
        try await health.load(); try await mindfulness.load()
        try await rest.load(); try await finance.load(); try await hobbies.load()

        // 12 days of energy and meal moving together.
        let cal = DayKey.calendar
        for offset in 0..<12 {
            let day = cal.date(from: DateComponents(year: 2026, month: 6, day: offset + 1))!
            try await health.logEnergy(min(offset / 2 + 1, 5), on: day)
            try await health.logMeal(min(offset / 2 + 1, 5), on: day)
        }

        let insights = InsightsStore(
            health: health, mindfulness: mindfulness, rest: rest, finance: finance, hobbies: hobbies
        )
        let series = insights.series()
        #expect(series.contains { $0.metricID == "energy" })
        #expect(series.contains { $0.metricID == "meal" })
        #expect(insights.topInsight != nil)
    }
}

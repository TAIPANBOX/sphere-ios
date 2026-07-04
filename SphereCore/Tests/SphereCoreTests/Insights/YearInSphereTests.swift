import Foundation
import Testing
@testable import SphereCore

@Suite("YearInSphere")
struct YearInSphereTests {
    @Test func introCardAlwaysPresent() {
        let cards = YearInSphere.cards(from: RecapStats(year: 2026))
        #expect(cards.count == 1)
        #expect(cards[0].id == "intro")
        #expect(cards[0].value == "Your 2026")
        #expect(YearInSphere.isEmpty(RecapStats(year: 2026)))
    }

    @Test func skipsZeroMetricsKeepsNonZero() {
        let stats = RecapStats(year: 2026, meditationMinutes: 600, workouts: 0, countriesVisited: 3)
        let cards = YearInSphere.cards(from: stats)
        let ids = cards.map(\.id)
        #expect(ids.contains("meditation"))
        #expect(ids.contains("countries"))
        #expect(!ids.contains("workouts"))
    }

    @Test func metricCardShowsFormattedValueAndCaption() {
        let cards = YearInSphere.cards(from: RecapStats(year: 2026, meditationMinutes: 1240))
        let card = cards.first { $0.id == "meditation" }!
        #expect(card.value == "1,240")
        #expect(card.caption == "minutes of calm")
        #expect(card.sphere == .mindfulness)
    }

    @Test func summaryLineListsTopMetrics() {
        let stats = RecapStats(year: 2026, meditationMinutes: 1240, workouts: 52, countriesVisited: 4)
        let line = YearInSphere.summaryLine(stats)
        #expect(line.hasPrefix("My 2026 in Sphere:"))
        #expect(line.contains("1,240 mindful minutes"))
        #expect(line.contains("52 workouts"))
        #expect(line.contains("4 countries"))
    }

    @Test func summaryLineGracefulWhenEmpty() {
        #expect(YearInSphere.summaryLine(RecapStats(year: 2026)).contains("a year of small steps"))
    }

    @Test func thousandsFormatting() {
        #expect(YearInSphere.formatted(999) == "999")
        #expect(YearInSphere.formatted(1000) == "1,000")
        #expect(YearInSphere.formatted(12345) == "12,345")
    }
}

@Suite("RecapStore")
@MainActor
struct RecapStoreTests {
    private let cal = Calendar(identifier: .gregorian)
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    private func makeStore(_ db: AppDatabase) -> (RecapStore, MindfulnessStore, HealthStore, TravelStore) {
        let mind = MindfulnessStore(database: db)
        let health = HealthStore(database: db)
        let travel = TravelStore(database: db)
        let store = RecapStore(
            mindfulness: mind, health: health, learning: LearningStore(database: db),
            travel: travel, goals: GoalsStore(database: db),
            creativity: CreativityStore(database: db), hobbies: HobbiesStore(database: db)
        )
        return (store, mind, health, travel)
    }

    @Test func aggregatesThisYearOnly() async throws {
        let db = try AppDatabase.inMemory()
        let (store, mind, health, travel) = makeStore(db)
        try await mind.add(MeditationSession(id: "m1", type: .breathing, durationMinutes: 20, date: day(2026, 3, 1)))
        try await mind.add(MeditationSession(id: "m2", type: .breathing, durationMinutes: 15, date: day(2025, 3, 1)))  // prior year
        try await mind.add(MeditationSession(id: "f1", type: .focus, durationMinutes: 50, date: day(2026, 4, 1)))
        try await health.addWorkout(Workout(id: "w1", type: .running, durationMinutes: 30, date: day(2026, 5, 1)))
        try await travel.addVisited(VisitedCountry(name: "Japan", flag: "🇯🇵", year: 2026))
        try await travel.addVisited(VisitedCountry(name: "Spain", flag: "🇪🇸", year: 2024))

        let stats = store.stats(year: 2026)
        #expect(stats.meditationMinutes == 20)      // 2025 excluded
        #expect(stats.focusMinutes == 50)
        #expect(stats.workouts == 1)
        #expect(stats.countriesVisited == 1)        // only Japan (2026)
    }

    @Test func cardsReflectAggregatedStats() async throws {
        let db = try AppDatabase.inMemory()
        let (store, mind, _, _) = makeStore(db)
        try await mind.add(MeditationSession(id: "m1", type: .breathing, durationMinutes: 40, date: day(2026, 3, 1)))
        let cards = store.cards(year: 2026)
        #expect(cards.contains { $0.id == "meditation" && $0.value == "40" })
    }
}

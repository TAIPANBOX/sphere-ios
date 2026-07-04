import Foundation
import Testing
@testable import SphereCore

@Suite("ExperimentStore")
@MainActor
struct ExperimentStoreTests {
    private func makeStore() throws -> ExperimentStore {
        let database = try AppDatabase.inMemory()
        let insights = InsightsStore(
            health: HealthStore(database: database),
            mindfulness: MindfulnessStore(database: database),
            rest: RestStore(database: database),
            finance: FinanceStore(database: database),
            hobbies: HobbiesStore(database: database)
        )
        return ExperimentStore(database: database, insights: insights)
    }

    @Test func startAndLoadRoundTrips() async throws {
        let store = try makeStore()
        let exp = try await store.start(title: "No caffeine after 2pm", durationDays: 14)
        #expect(exp.status == .running)
        #expect(store.running.count == 1)

        try await store.load()
        #expect(store.experiments.contains { $0.title == "No caffeine after 2pm" })
    }

    @Test func completingMovesOutOfRunning() async throws {
        let store = try makeStore()
        let exp = try await store.start(title: "Walk daily", durationDays: 7)
        try await store.setStatus(exp, .completed)
        #expect(store.running.isEmpty)
        #expect(store.experiments.first?.status == .completed)
    }

    @Test func activeExperimentPicksNearestToDone() async throws {
        let store = try makeStore()
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 20))!
        let older = cal.date(from: DateComponents(year: 2026, month: 6, day: 8))!
        let newer = cal.date(from: DateComponents(year: 2026, month: 6, day: 18))!
        _ = try await store.start(title: "Older", durationDays: 30, startDate: older, now: older)
        _ = try await store.start(title: "Newer", durationDays: 30, startDate: newer, now: newer)
        // "Older" has more days elapsed as of now → surfaced first.
        #expect(store.activeExperiment(asOf: now)?.title == "Older")
    }

    @Test func removeDeletes() async throws {
        let store = try makeStore()
        let exp = try await store.start(title: "Temp", durationDays: 7)
        try await store.remove(exp)
        #expect(store.experiments.isEmpty)
    }

    @Test func analysisIsEmptyWithoutLoggedData() async throws {
        let store = try makeStore()
        let exp = try await store.start(title: "No data yet", durationDays: 14)
        #expect(store.analysis(for: exp).isEmpty)
    }
}

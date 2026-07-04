import Foundation
import Testing
@testable import SphereCore

@Suite("ReadinessStore")
@MainActor
struct ReadinessStoreTests {
    private func makeStore() throws -> (ReadinessStore, RestStore, HealthStore) {
        let database = try AppDatabase.inMemory()
        let rest = RestStore(database: database)
        let mindfulness = MindfulnessStore(database: database)
        let health = HealthStore(database: database)
        let store = ReadinessStore(
            database: database, rest: rest, mindfulness: mindfulness, health: health
        )
        return (store, rest, health)
    }

    @Test func verdictReflectsLoggedSleep() async throws {
        let (store, rest, _) = try makeStore()
        try await rest.add(SleepEntry(id: "s1", date: Date(), hoursSlept: 8))
        let verdict = store.verdict()
        // 8h vs 8h goal (60) + unknown stress (20) = 80 → high band.
        #expect(verdict.score == 80)
        #expect(verdict.band == .high)
    }

    @Test func recordPredictionPersistsAndReloads() async throws {
        let (store, rest, _) = try makeStore()
        try await rest.add(SleepEntry(id: "s1", date: Date(), hoursSlept: 8))
        await store.recordPrediction()
        try await store.loadLedger()
        #expect(store.predictions[DayKey.make()] == 80)
    }

    @Test func feltEnergyRatingIsStored() async throws {
        let (store, _, health) = try makeStore()
        await store.rateEnergy(4)
        #expect(health.todayEnergy() == 4)
        #expect(store.todayEnergy() == 4)
    }

    @Test func correctionAdaptsAcrossDays() async throws {
        let (store, rest, health) = try makeStore()
        let cal = Calendar(identifier: .gregorian)
        // Three past days: predicted 80 (8h sleep) but only felt 2/5 (=40).
        for offset in 1...3 {
            let day = cal.date(byAdding: .day, value: -offset, to: Date())!
            try await rest.add(SleepEntry(id: "s\(offset)", date: day, hoursSlept: 8))
            await store.recordPrediction(asOf: day)
            try await health.logEnergy(2, on: day)
        }
        // Today: 8h sleep again → raw 80, but the learned correction pulls it down.
        try await rest.add(SleepEntry(id: "today", date: Date(), hoursSlept: 8))
        let verdict = store.verdict()
        #expect(verdict.score < 80)
    }
}

import Foundation
import Testing
@testable import SphereCore

@Suite("One-tap logs: energy, meal, gratitude, affirmations")
@MainActor
struct OneTapLogsTests {
    private func makeHealth() throws -> (HealthStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (HealthStore(database: database), database)
    }

    @Test func energyAndMealPersistPerDay() async throws {
        let (store, database) = try makeHealth()
        try await store.load()
        #expect(store.todayEnergy() == nil)

        try await store.logEnergy(4)
        try await store.logMeal(3)
        try await store.logEnergy(5) // overwrites today
        #expect(store.todayEnergy() == 5)
        #expect(store.todayMeal() == 3)

        let reloaded = HealthStore(database: database)
        try await reloaded.load()
        #expect(reloaded.todayEnergy() == 5)
        #expect(reloaded.todayMeal() == 3)
    }

    @Test func energyMealToolsAndSnapshot() async throws {
        let (store, _) = try makeHealth()
        try await store.load()
        let registry = SphereToolRegistry(tools: store.tools)

        #expect(!(await registry.execute(
            LLMToolCall(id: "e", name: "log_energy", input: ["level": 4])
        )).isError)
        #expect(store.todayEnergy() == 4)

        let snapshot = await registry.execute(
            LLMToolCall(id: "s", name: "get_health_today", input: .object([:]))
        )
        #expect(JSONValue.decoded(from: snapshot.content)?["energyToday"]?.intValue == 4)
    }

    @Test func captureParsesEnergyAndMeal() {
        let calls = CaptureRuleParser.parse("energy 4, meal 3")
        #expect(calls.map(\.name).sorted() == ["log_energy", "log_meal"])
    }

    @Test func gratitudePersistsAndNotesToday() async throws {
        let database = try AppDatabase.inMemory()
        let store = MindfulnessStore(database: database)
        try await store.load()
        #expect(!store.hasGratitudeToday())

        try await store.addGratitude("  a sunny walk  ")
        try await store.addGratitude("") // ignored
        #expect(store.gratitude.count == 1)
        #expect(store.gratitude.first?.content == "a sunny walk")
        #expect(store.hasGratitudeToday())

        let reloaded = MindfulnessStore(database: database)
        try await reloaded.load()
        #expect(reloaded.gratitude.count == 1)
    }

    @Test func affirmationDefaultsToSeedThenCustom() async throws {
        let database = try AppDatabase.inMemory()
        let store = MindfulnessStore(database: database)
        try await store.load()
        // With no custom ones, a seed is returned and is stable for the day.
        let seed = store.dailyAffirmation()
        #expect(Affirmation.seeds.contains(seed))
        #expect(store.dailyAffirmation() == seed)

        try await store.addAffirmation("I've got this")
        #expect(store.customAffirmations.count == 1)
        // Now the daily pick comes from the custom pool.
        #expect(store.dailyAffirmation() == "I've got this")
    }
}

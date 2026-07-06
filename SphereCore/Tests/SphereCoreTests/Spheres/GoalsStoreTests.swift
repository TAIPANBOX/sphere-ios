import Foundation
import Testing
@testable import SphereCore

@Suite("GoalsStore")
@MainActor
struct GoalsStoreTests {
    private func makeStore(engram: EngramStore? = nil) throws -> (GoalsStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (GoalsStore(database: database, engram: engram), database)
    }

    @Test func addPersistsAcrossStoreInstances() async throws {
        let (store, database) = try makeStore()
        try await store.add(Goal(id: "g1", title: "Learn Swift", horizon: .quarter))
        try await store.add(Goal(id: "g2", title: "Run a marathon"))

        let reloaded = GoalsStore(database: database)
        try await reloaded.load()
        #expect(reloaded.goals.map(\.title) == ["Learn Swift", "Run a marathon"])
        #expect(reloaded.goals[0].horizon == .quarter)
    }

    @Test func keyResultsSurviveRoundTrip() async throws {
        let (store, database) = try makeStore()
        try await store.add(Goal(
            id: "g1", title: "Ship Sphere iOS",
            keyResults: ["Port Engram", "12 spheres", "App Store release"]
        ))

        let reloaded = GoalsStore(database: database)
        try await reloaded.load()
        #expect(reloaded.goals[0].keyResults.count == 3)
        #expect(reloaded.goals[0].keyResults[2] == "App Store release")
    }

    @Test func setProgressClampsAndCompletes() async throws {
        let (store, _) = try makeStore()
        try await store.add(Goal(id: "g1", title: "Read 12 books"))

        try await store.setProgress(id: "g1", percent: 150)
        #expect(store.goals[0].progressPercent == 100)
        #expect(store.goals[0].status == .completed)

        try await store.setProgress(id: "g1", percent: -5)
        #expect(store.goals[0].progressPercent == 0)
        #expect(store.goals[0].status == .active)
    }

    @Test func toggleStatusPausesAndResumes() async throws {
        let (store, _) = try makeStore()
        try await store.add(Goal(id: "g1", title: "Guitar"))

        try await store.toggleStatus(id: "g1")
        #expect(store.goals[0].status == .paused)
        try await store.toggleStatus(id: "g1")
        #expect(store.goals[0].status == .active)
    }

    @Test func overallProgressIgnoresPausedGoals() async throws {
        let (store, _) = try makeStore()
        try await store.add(Goal(id: "g1", title: "A", progressPercent: 80))
        try await store.add(Goal(id: "g2", title: "B", progressPercent: 40))
        try await store.add(Goal(id: "g3", title: "C", status: .paused, progressPercent: 0))

        #expect(store.overallProgress == 60)
    }

    @Test func removeDeletesFromStateAndDisk() async throws {
        let (store, database) = try makeStore()
        try await store.add(Goal(id: "g1", title: "Temp"))
        try await store.remove(id: "g1")
        #expect(store.goals.isEmpty)

        let reloaded = GoalsStore(database: database)
        try await reloaded.load()
        #expect(reloaded.goals.isEmpty)
    }

    @Test func addNotesIntoEngram() async throws {
        let engram = try EngramStore.inMemory()
        let (store, _) = try makeStore(engram: engram)
        try await store.add(Goal(id: "g1", title: "Meditate daily", horizon: .month))

        var count = 0
        for _ in 0..<50 where count == 0 {
            count = try await engram.count(agentId: "goals")
            if count == 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(count == 1)
        let memories = try await engram.recall("goal", agentId: "goals")
        #expect(memories.first?.content == "New goal set: Meditate daily (month)")
    }

    @Test func habitsToggleAndPersist() async throws {
        let (store, database) = try makeStore()
        try await store.addHabit(Habit(id: "h1", name: "Morning meditation"))

        try await store.toggleHabit(id: "h1")
        #expect(store.habits[0].checkedIn())
        #expect(store.habits[0].streak() == 1)

        try await store.toggleHabit(id: "h1")
        #expect(!store.habits[0].checkedIn())

        try await store.toggleHabit(id: "h1")
        let reloaded = GoalsStore(database: database)
        try await reloaded.load()
        #expect(reloaded.habits[0].checkedIn())
    }

    @Test func checkInHabitIsIdempotent() async throws {
        let (store, database) = try makeStore()
        try await store.addHabit(Habit(id: "h1", name: "Read"))

        try await store.checkInHabit(id: "h1")
        #expect(store.habits[0].checkedIn())
        #expect(store.habits[0].checkInDates.count == 1)

        // A second call (e.g. the notification action firing twice) is a no-op.
        try await store.checkInHabit(id: "h1")
        #expect(store.habits[0].checkInDates.count == 1)

        let reloaded = GoalsStore(database: database)
        try await reloaded.load()
        #expect(reloaded.habits[0].checkedIn())
    }

    // MARK: - Agent tools

    @Test func addGoalToolCreatesGoalAndConfirms() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(
            id: "t1", name: "add_goal",
            input: ["title": "Visit Japan", "horizon": "year", "emoji": "🗾"]
        )
        let result = await registry.execute(call)
        #expect(!result.isError)

        #expect(store.goals.count == 1)
        #expect(store.goals[0].title == "Visit Japan")
        #expect(store.goals[0].emoji == "🗾")
        #expect(registry.confirmation(for: call) == "Added goal: Visit Japan")
    }

    @Test func addGoalToolRejectsMissingTitle() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)

        let result = await registry.execute(
            LLMToolCall(id: "t1", name: "add_goal", input: .object([:]))
        )
        #expect(result.isError)
        #expect(store.goals.isEmpty)
    }

    @Test func listGoalsToolIsSilentAndReturnsSnapshot() async throws {
        let (store, _) = try makeStore()
        try await store.add(Goal(id: "g1", title: "Learn Ukrainian", progressPercent: 35))
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(id: "t1", name: "list_goals", input: .object([:]))
        let result = await registry.execute(call)
        let json = JSONValue.decoded(from: result.content)

        #expect(json?["count"]?.intValue == 1)
        #expect(json?["goals"]?[0]?["title"]?.stringValue == "Learn Ukrainian")
        #expect(json?["goals"]?[0]?["progress"]?.intValue == 35)
        #expect(registry.confirmation(for: call) == nil)
    }

    @Test func toolsAreScopedToGoalsSphere() throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)
        #expect(registry.toolsFor(.goals).map(\.name).sorted() == ["add_goal", "list_goals"])
        #expect(registry.toolsFor(.health).isEmpty)
    }
}

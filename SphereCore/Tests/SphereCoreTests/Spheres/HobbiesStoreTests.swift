import Foundation
import Testing
@testable import SphereCore

@Suite("HobbiesStore")
@MainActor
struct HobbiesStoreTests {
    private func makeStore(engram: EngramStore? = nil) throws -> (HobbiesStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (HobbiesStore(database: database, engram: engram), database)
    }

    @Test func weeklyAndTotalMinutesUseTimeWindows() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        try await store.addHobby(Hobby(id: "h1", name: "Guitar", targetMinutesPerWeek: 120))
        try await store.logSession(HobbySession(id: "s1", hobbyId: "h1", durationMinutes: 45, date: now))
        try await store.logSession(HobbySession(
            id: "s2", hobbyId: "h1", durationMinutes: 30, date: now.addingTimeInterval(-3 * 86_400)
        ))
        try await store.logSession(HobbySession(
            id: "s3", hobbyId: "h1", durationMinutes: 60, date: now.addingTimeInterval(-10 * 86_400)
        ))

        #expect(store.weeklyMinutes(for: "h1", asOf: now) == 75)
        #expect(store.totalMinutes(for: "h1") == 135)
        #expect(store.totalWeeklyMinutes(asOf: now) == 75)
    }

    @Test func removeHobbyCascadesSessions() async throws {
        let (store, database) = try makeStore()
        try await store.addHobby(Hobby(id: "h1", name: "Cooking"))
        try await store.addHobby(Hobby(id: "h2", name: "Photo"))
        try await store.logSession(HobbySession(id: "s1", hobbyId: "h1", durationMinutes: 30, date: Date()))
        try await store.logSession(HobbySession(id: "s2", hobbyId: "h2", durationMinutes: 20, date: Date()))

        try await store.removeHobby(id: "h1")
        #expect(store.sessions.map(\.id) == ["s2"])

        let reloaded = HobbiesStore(database: database)
        try await reloaded.load()
        #expect(reloaded.sessions.map(\.id) == ["s2"])
        #expect(reloaded.hobbies.map(\.id) == ["h2"])
    }

    @Test func hobbyEditingLifecycle() async throws {
        let (store, database) = try makeStore()
        try await store.addHobby(Hobby(id: "h1", name: "Guitar"))

        try await store.toggleActive(id: "h1")
        try await store.setGoal(id: "h1", goal: "Play Wonderwall")
        try await store.addEquipment(id: "h1", item: "Capo")
        try await store.addEquipment(id: "h1", item: "Picks")
        try await store.removeEquipment(id: "h1", at: 0)
        try await store.addResource(id: "h1", resource: "JustinGuitar")

        let reloaded = HobbiesStore(database: database)
        try await reloaded.load()
        let hobby = try #require(reloaded.hobbies.first)
        #expect(!hobby.isActive)
        #expect(hobby.goal == "Play Wonderwall")
        #expect(hobby.equipment == ["Picks"])
        #expect(hobby.resources == ["JustinGuitar"])
    }

    @Test func sessionNoteLandsInEngram() async throws {
        let engram = try EngramStore.inMemory()
        let (store, _) = try makeStore(engram: engram)
        try await store.addHobby(Hobby(id: "h1", name: "Cooking"))
        try await store.logSession(HobbySession(
            id: "s1", hobbyId: "h1", durationMinutes: 45, date: Date(),
            note: "Thai green curry — turned out amazing"
        ))

        var count = 0
        for _ in 0..<50 where count < 2 {
            count = try await engram.count(agentId: "hobbies")
            if count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        }
        let memories = try await engram.recall("curry", agentId: "hobbies")
        #expect(memories.first?.content == "Cooking session, 45 min — Thai green curry — turned out amazing")
    }

    // MARK: - Agent tools

    @Test func logHobbySessionToolMatchesByNameCaseInsensitive() async throws {
        let (store, _) = try makeStore()
        try await store.addHobby(Hobby(id: "h1", name: "Guitar"))
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(
            id: "t1", name: "log_hobby_session",
            input: ["hobby": "guitar", "minutes": 45, "note": "learned a new riff"]
        )
        let result = await registry.execute(call)
        #expect(!result.isError)
        #expect(store.sessions.first?.hobbyId == "h1")
        #expect(registry.confirmation(for: call) == "Logged 45 min of guitar")
    }

    @Test func logHobbySessionToolExplainsUnknownHobby() async throws {
        let (store, _) = try makeStore()
        try await store.addHobby(Hobby(id: "h1", name: "Guitar"))
        try await store.addHobby(Hobby(id: "h2", name: "Cooking"))
        let registry = SphereToolRegistry(tools: store.tools)

        let result = await registry.execute(LLMToolCall(
            id: "t1", name: "log_hobby_session", input: ["hobby": "Chess", "minutes": 30]
        ))
        #expect(result.isError)
        #expect(result.content.contains("Guitar"))
        #expect(result.content.contains("Cooking"))
        #expect(store.sessions.isEmpty)
    }

    @Test func hobbiesSummaryToolIsSilentAndComplete() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        try await store.addHobby(Hobby(id: "h1", name: "Guitar", targetMinutesPerWeek: 120))
        try await store.logSession(HobbySession(id: "s1", hobbyId: "h1", durationMinutes: 45, date: now))
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(id: "t1", name: "get_hobbies_summary", input: .object([:]))
        let result = await registry.execute(call)
        let json = JSONValue.decoded(from: result.content)

        #expect(json?["hobbies"]?[0]?["name"]?.stringValue == "Guitar")
        #expect(json?["hobbies"]?[0]?["weeklyMinutes"]?.intValue == 45)
        #expect(json?["hobbies"]?[0]?["targetMinutesPerWeek"]?.intValue == 120)
        #expect(json?["recentSessions"]?[0]?["hobby"]?.stringValue == "Guitar")
        #expect(registry.confirmation(for: call) == nil)
    }

    @Test func toolsAreScopedToHobbiesSphere() throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)
        #expect(
            registry.toolsFor(.hobbies).map(\.name).sorted()
                == ["get_hobbies_summary", "log_hobby_session"]
        )
        #expect(registry.toolsFor(.creativity).isEmpty)
    }
}

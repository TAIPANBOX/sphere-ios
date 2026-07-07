import Foundation
import Testing
@testable import SphereCore

@Suite("EngramStore")
struct EngramStoreTests {
    @Test func observeStoresRecallableMemory() async throws {
        let store = try EngramStore.inMemory()
        try await store.observe(
            agentId: "health", content: "User ran 5 km in the morning",
            tags: ["exercise"], salience: 0.8
        )
        #expect(try await store.count(agentId: "health") == 1)
    }

    @Test func observeIgnoresEmptyContent() async throws {
        let store = try EngramStore.inMemory()
        let id = try await store.observe(agentId: "health", content: "   ")
        #expect(id == nil)
        #expect(try await store.count(agentId: "health") == 0)
    }

    @Test func recallReturnsRequestedAgentOnly() async throws {
        let store = try EngramStore.inMemory()
        try await store.observe(agentId: "health", content: "Slept 8 hours")
        try await store.observe(agentId: "finance", content: "Spent 50 on groceries")

        let healthHits = try await store.recall("sleep", agentId: "health")
        #expect(!healthHits.isEmpty)
        #expect(healthHits.allSatisfy { $0.agentId == "health" })

        let financeHits = try await store.recall("groceries", agentId: "finance")
        #expect(!financeHits.isEmpty)
        #expect(financeHits.allSatisfy { $0.agentId == "finance" })
    }

    @Test func crossAgentRecallSpansAgents() async throws {
        let store = try EngramStore.inMemory()
        try await store.observe(agentId: "health", content: "Sleep quality was great last night")
        try await store.observe(agentId: "mindfulness", content: "Felt calm after sleep meditation")
        try await store.observe(agentId: "finance", content: "Paid rent")

        let hits = try await store.crossAgentRecall("sleep")
        let agentIds = Set(hits.map(\.agentId))
        #expect(agentIds.isSuperset(of: ["health", "mindfulness"]))
    }

    @Test func emptyQueryFallsBackToRecent() async throws {
        let store = try EngramStore.inMemory()
        try await store.observe(agentId: "career", content: "First note")
        try await store.observe(agentId: "career", content: "Second note")

        let hits = try await store.recall("", agentId: "career")
        #expect(hits.count == 2)
        #expect(hits.first?.content == "Second note")
    }

    @Test func formatMemoriesWrapsInMemoryTags() async throws {
        let store = try EngramStore.inMemory()
        try await store.observe(agentId: "home", content: "Bought light bulbs")
        let memories = try await store.recall("bulbs", agentId: "home")
        let context = formatMemoriesAsContext(memories)
        #expect(context.hasPrefix("<memory>"))
        #expect(context.hasSuffix("</memory>"))
        #expect(context.contains("Bought light bulbs"))
    }

    @Test func formatMemoriesEmptyForNoMemories() {
        #expect(formatMemoriesAsContext([]) == "")
    }

    @Test func countAllSumsAcrossAgents() async throws {
        let store = try EngramStore.inMemory()
        try await store.observe(agentId: "a", content: "one")
        try await store.observe(agentId: "b", content: "two")
        try await store.observe(agentId: "a", content: "three")
        #expect(try await store.countAll() == 3)
    }

    @Test(arguments: [
        "React",
        "\"React\"",
        "React?",
        "React!",
        "React's hooks",
        "React + Redux",
        "React AND hooks",
        "React (advanced)",
        "C++ patterns",
        "*react*",
    ])
    func recallSurvivesFtsSpecialChars(query: String) async throws {
        let store = try EngramStore.inMemory()
        try await store.observe(agentId: "learning", content: "Reading the book about React")

        let hits = try await store.recall(query, agentId: "learning")
        #expect(!hits.isEmpty, "query \(query) should still return the React memory")
        #expect(hits.first?.content.contains("React") == true)
    }

    @Test func allPunctuationQueryFallsBackToRecent() async throws {
        let store = try EngramStore.inMemory()
        try await store.observe(agentId: "home", content: "note one")

        let hits = try await store.recall("!@#$%^&*()", agentId: "home")
        #expect(!hits.isEmpty)
        #expect(hits.first?.content == "note one")
    }

    @Test func ukrainianContentIsRecallable() async throws {
        let store = try EngramStore.inMemory()
        try await store.observe(agentId: "health", content: "Пробіг 5 кілометрів зранку")

        let hits = try await store.recall("пробіг", agentId: "health")
        #expect(hits.first?.content.contains("кілометрів") == true)
    }

    @Test func recallIncrementsAccessStats() async throws {
        let store = try EngramStore.inMemory()
        let id = try await store.observe(agentId: "health", content: "Morning yoga session")
        let memoryId = try #require(id)

        for _ in 0..<3 {
            _ = try await store.recall("yoga", agentId: "health")
        }

        let memory = try #require(try await store.memory(id: memoryId))
        #expect(memory.accessCount == 3)
    }

    @Test func dumpAllReturnsEveryMemoryInCreationOrder() async throws {
        let store = try EngramStore.inMemory()
        try await store.observe(agentId: "health", content: "First observation", tags: ["a"])
        try await store.observe(agentId: "finance", content: "Second observation", tags: ["b"])

        let dump = try await store.dumpAll()
        #expect(dump.count == 2)
        #expect(dump.map(\.content) == ["First observation", "Second observation"])
        #expect(Set(dump.map(\.agentId)) == ["health", "finance"])
    }

    @Test func dumpAllEmptyStoreReturnsEmpty() async throws {
        let store = try EngramStore.inMemory()
        #expect(try await store.dumpAll().isEmpty)
    }

    @Test func noteIsFireAndForget() async throws {
        let store = try EngramStore.inMemory()
        store.note(agentId: "goals", content: "Started a new habit")

        var count = 0
        for _ in 0..<50 where count == 0 {
            count = try await store.count(agentId: "goals")
            if count == 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(count == 1)
    }
}

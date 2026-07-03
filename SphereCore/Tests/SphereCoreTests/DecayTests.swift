import Foundation
import Testing
@testable import SphereCore

@Suite("Decay")
struct DecayTests {
    @Test func importanceFormulaMatchesReference() {
        // Reference values from the Python Engram implementation:
        // salience * exp(-lambda * days) + alpha * log1p(access) + beta * valence
        let config = DecayConfig()
        let now = Date()

        let fresh = config.importance(
            salience: 0.8, emotionalValence: 0, lastAccess: now, accessCount: 0, now: now
        )
        #expect(abs(fresh - 0.8) < 1e-9)

        let thirtyDaysOld = config.importance(
            salience: 0.9, emotionalValence: 0,
            lastAccess: now.addingTimeInterval(-30 * 86_400), accessCount: 0, now: now
        )
        #expect(abs(thirtyDaysOld - 0.9 * exp(-3)) < 1e-9)

        let reinforced = config.importance(
            salience: 0.9, emotionalValence: 0,
            lastAccess: now.addingTimeInterval(-30 * 86_400), accessCount: 5, now: now
        )
        #expect(abs(reinforced - (0.9 * exp(-3) + 0.2 * log1p(5))) < 1e-9)
    }

    @Test func clockSkewCannotInflateImportance() {
        let config = DecayConfig()
        let now = Date()
        let future = config.importance(
            salience: 0.5, emotionalValence: 0,
            lastAccess: now.addingTimeInterval(60), accessCount: 0, now: now
        )
        #expect(abs(future - 0.5) < 1e-9)
    }

    @Test func decayLowersImportanceOfStaleMemories() async throws {
        let store = try EngramStore.inMemory()
        let id = try #require(
            try await store.observe(agentId: "rest", content: "Went to bed at 23:00", salience: 0.9)
        )

        let thirtyDaysLater = Date().addingTimeInterval(30 * 86_400)
        let updated = try await store.runDecay(now: thirtyDaysLater)
        #expect(updated == 1)

        let memory = try #require(try await store.memory(id: id))
        #expect(memory.importance < 0.05)
    }

    @Test func accessReinforcementKeepsMemoriesAlive() async throws {
        let store = try EngramStore.inMemory()
        let staleId = try #require(
            try await store.observe(agentId: "rest", content: "Watched a movie", salience: 0.9)
        )
        let usedId = try #require(
            try await store.observe(agentId: "rest", content: "Evening walk habit", salience: 0.9)
        )

        for _ in 0..<5 {
            _ = try await store.recall("walk habit", agentId: "rest")
        }

        try await store.runDecay(now: Date().addingTimeInterval(30 * 86_400))

        let stale = try #require(try await store.memory(id: staleId))
        let used = try #require(try await store.memory(id: usedId))
        #expect(used.importance > stale.importance)
        #expect(used.importance > DecayConfig().threshold)
    }

    @Test func pruneRemovesOnlyLowImportanceMemories() async throws {
        let store = try EngramStore.inMemory()
        try await store.observe(agentId: "rest", content: "Forgettable detail", salience: 0.3)
        let keptId = try #require(
            try await store.observe(agentId: "rest", content: "Important routine", salience: 0.9)
        )

        // 20 days: 0.3 * exp(-2) ≈ 0.04 (prunable), 0.9 * exp(-2) ≈ 0.12 (kept).
        try await store.runDecay(now: Date().addingTimeInterval(20 * 86_400))
        let pruned = try await store.prune()

        #expect(pruned == 1)
        #expect(try await store.countAll() == 1)
        #expect(try await store.memory(id: keptId) != nil)

        // The FTS index must stay in sync after pruning.
        let hits = try await store.recall("routine", agentId: "rest")
        #expect(hits.first?.id == keptId)
    }

    @Test func decayOnEmptyStoreIsNoop() async throws {
        let store = try EngramStore.inMemory()
        #expect(try await store.runDecay() == 0)
        #expect(try await store.prune() == 0)
    }
}

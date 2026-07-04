import Foundation
import Testing
@testable import SphereCore

@Suite("SavingsGoal model")
struct SavingsGoalModelTests {
    @Test func percentAndRemainingClamp() {
        let half = SavingsGoal(id: "g", name: "Trip", target: 1_000, saved: 400)
        #expect(abs(half.percent - 0.4) < 1e-9)
        #expect(half.remaining == 600)

        let over = SavingsGoal(id: "g", name: "Trip", target: 1_000, saved: 1_500)
        #expect(over.percent == 1)
        #expect(over.remaining == 0)

        let zeroTarget = SavingsGoal(id: "g", name: "X", target: 0, saved: 50)
        #expect(zeroTarget.percent == 0)
    }
}

@Suite("FinanceStore accounts & savings")
@MainActor
struct FinanceSecondaryTests {
    private func makeStore(engram: EngramStore? = nil) throws -> (FinanceStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (FinanceStore(database: database, engram: engram), database)
    }

    @Test func accountsPersistAndTotal() async throws {
        let (store, database) = try makeStore()
        try await store.addAccount(Account(id: "a1", name: "Checking", type: .checking, balance: 1_200))
        try await store.addAccount(Account(id: "a2", name: "Piggy", type: .savings, balance: 3_400))
        #expect(store.totalAccountBalance == 4_600)

        var updated = store.accounts[0]
        updated.balance = 1_500
        try await store.updateAccount(updated)
        #expect(store.totalAccountBalance == 4_900)

        let reloaded = FinanceStore(database: database)
        try await reloaded.load()
        #expect(reloaded.accounts.count == 2)
        #expect(reloaded.totalAccountBalance == 4_900)

        try await store.removeAccount(id: "a1")
        #expect(store.accounts.map(\.id) == ["a2"])
    }

    @Test func savingsGoalsAddWithdrawAndNote() async throws {
        let engram = try EngramStore.inMemory()
        let (store, database) = try makeStore(engram: engram)
        try await store.addSavingsGoal(SavingsGoal(id: "g1", name: "New laptop", target: 2_000, saved: 500))

        try await store.addToSavings(id: "g1", amount: 300)
        #expect(store.savingsGoals[0].saved == 800)
        // Withdrawing never drops below zero.
        try await store.addToSavings(id: "g1", amount: -5_000)
        #expect(store.savingsGoals[0].saved == 0)

        let reloaded = FinanceStore(database: database)
        try await reloaded.load()
        #expect(reloaded.savingsGoals.first?.name == "New laptop")

        var count = 0
        for _ in 0..<50 where count == 0 {
            count = try await engram.count(agentId: "finance")
            if count == 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        let memories = try await engram.recall("savings goal", agentId: "finance")
        #expect(memories.contains { $0.content == "New savings goal: New laptop (target 2000)" })
    }

    @Test func financeSummaryIncludesAccountsAndSavings() async throws {
        let (store, _) = try makeStore()
        try await store.load()
        try await store.addAccount(Account(id: "a1", name: "Checking", balance: 1_000))
        try await store.addSavingsGoal(SavingsGoal(id: "g1", name: "Trip", target: 1_000, saved: 250))
        let registry = SphereToolRegistry(tools: store.tools)

        let result = await registry.execute(
            LLMToolCall(id: "t1", name: "get_finance_summary", input: .object([:]))
        )
        let json = JSONValue.decoded(from: result.content)
        #expect(json?["totalAccountBalance"]?.doubleValue == 1_000)
        #expect(json?["savingsGoals"]?[0]?["name"]?.stringValue == "Trip")
        #expect(json?["savingsGoals"]?[0]?["percent"]?.intValue == 25)
    }
}

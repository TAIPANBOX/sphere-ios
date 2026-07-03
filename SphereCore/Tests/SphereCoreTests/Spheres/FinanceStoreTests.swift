import Foundation
import Testing
@testable import SphereCore

@Suite("FinanceStore")
@MainActor
struct FinanceStoreTests {
    private func makeStore(engram: EngramStore? = nil) throws -> (FinanceStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (FinanceStore(database: database, engram: engram), database)
    }

    private func tx(
        _ id: String,
        _ title: String,
        _ amount: Double,
        type: TransactionType = .expense,
        category: TransactionCategory = .food,
        date: Date = Date()
    ) -> Transaction {
        Transaction(id: id, title: title, amount: amount, type: type, category: category, date: date)
    }

    // MARK: - Transactions

    @Test func addKeepsNewestFirstAndComputesTotals() async throws {
        let (store, database) = try makeStore()
        try await store.add(tx("t1", "Salary", 3000, type: .income, category: .salary))
        try await store.add(tx("t2", "Coffee", 4.5))
        try await store.add(tx("t3", "Groceries", 60))

        #expect(store.transactions.map(\.id) == ["t3", "t2", "t1"])
        #expect(store.totalIncome == 3000)
        #expect(store.totalExpenses == 64.5)
        #expect(store.balance == 2935.5)

        let reloaded = FinanceStore(database: database)
        try await reloaded.load()
        #expect(reloaded.transactions.map(\.id) == ["t3", "t2", "t1"])
    }

    @Test func addNotesIntoEngram() async throws {
        let engram = try EngramStore.inMemory()
        let (store, _) = try makeStore(engram: engram)
        try await store.add(tx("t1", "Coffee", 4.6, category: .food))

        var count = 0
        for _ in 0..<50 where count == 0 {
            count = try await engram.count(agentId: "finance")
            if count == 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        let memories = try await engram.recall("coffee", agentId: "finance")
        #expect(memories.first?.content == "Logged expense 5: Coffee (food)")
    }

    @Test func removeDeletesFromStateAndDisk() async throws {
        let (store, database) = try makeStore()
        try await store.add(tx("t1", "Temp", 10))
        try await store.remove(id: "t1")
        #expect(store.transactions.isEmpty)

        let reloaded = FinanceStore(database: database)
        try await reloaded.load()
        #expect(reloaded.transactions.isEmpty)
    }

    // MARK: - Budgets

    @Test func setBudgetUpsertsPerCategory() async throws {
        let (store, database) = try makeStore()
        try await store.setBudget(category: .food, limit: 300)
        try await store.setBudget(category: .food, limit: 400)
        try await store.setBudget(category: .transport, limit: 100)

        #expect(store.budgets.count == 2)
        #expect(store.budgets.first { $0.category == .food }?.limit == 400)

        let reloaded = FinanceStore(database: database)
        try await reloaded.load()
        #expect(reloaded.budgets.count == 2)

        try await store.removeBudget(id: "food")
        #expect(store.budgets.map(\.category) == [.transport])
    }

    @Test func spentThisMonthCountsOnlyThisMonthsExpenses() async throws {
        let (store, _) = try makeStore()
        let now = Date()
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: now)!

        try await store.add(tx("t1", "Groceries", 50, category: .food, date: now))
        try await store.add(tx("t2", "Cafe", 20, category: .food, date: now))
        try await store.add(tx("t3", "Old", 500, category: .food, date: lastMonth))
        try await store.add(tx("t4", "Bus", 5, category: .transport, date: now))
        try await store.add(tx("t5", "Refund", 30, type: .income, category: .food, date: now))

        #expect(store.spentThisMonth(in: .food, asOf: now) == 70)
        #expect(store.spentThisMonth(in: .transport, asOf: now) == 5)
    }

    @Test func overBudgetFlagsExceededCategories() async throws {
        let (store, _) = try makeStore()
        try await store.setBudget(category: .food, limit: 60)
        try await store.setBudget(category: .transport, limit: 100)
        try await store.add(tx("t1", "Groceries", 80, category: .food))
        try await store.add(tx("t2", "Bus", 5, category: .transport))

        #expect(store.overBudget().map(\.category) == [.food])
    }

    // MARK: - Subscriptions

    @Test func subscriptionsToggleAndMonthlyTotal() async throws {
        let (store, database) = try makeStore()
        try await store.addSubscription(Subscription(id: "s1", name: "Music", amount: 10, billingDay: 5))
        try await store.addSubscription(Subscription(id: "s2", name: "Cloud", amount: 3, billingDay: 20))

        #expect(store.totalMonthlySubscriptions == 13)

        try await store.toggleSubscription(id: "s2")
        #expect(store.totalMonthlySubscriptions == 10)

        let reloaded = FinanceStore(database: database)
        try await reloaded.load()
        #expect(reloaded.subscriptions.first { $0.id == "s2" }?.isActive == false)

        try await store.removeSubscription(id: "s1")
        #expect(store.subscriptions.map(\.id) == ["s2"])
    }

    @Test func daysUntilBillingRollsToNextMonth() {
        let calendar = Calendar.current
        // Fix "now" to the 10th so both directions are deterministic.
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10))!

        #expect(Subscription(id: "s", name: "A", amount: 1, billingDay: 15).daysUntilBilling(asOf: now) == 5)
        #expect(Subscription(id: "s", name: "B", amount: 1, billingDay: 10).daysUntilBilling(asOf: now) == 0)
        // Day 5 already passed in July → August 5th.
        #expect(Subscription(id: "s", name: "C", amount: 1, billingDay: 5).daysUntilBilling(asOf: now) == 26)
    }

    // MARK: - Agent tools

    @Test func addTransactionToolCreatesAndConfirms() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(
            id: "t1", name: "add_transaction",
            input: ["title": "Coffee", "amount": 4.5, "type": "expense", "category": "food"]
        )
        let result = await registry.execute(call)
        #expect(!result.isError)
        #expect(store.transactions.count == 1)
        #expect(store.transactions[0].title == "Coffee")
        #expect(store.transactions[0].category == .food)
        #expect(registry.confirmation(for: call) == "Logged expense 4.5 — Coffee (food)")
    }

    @Test func addTransactionToolValidatesInput() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)

        let noAmount = await registry.execute(LLMToolCall(
            id: "t1", name: "add_transaction",
            input: ["title": "Coffee", "type": "expense", "category": "food"]
        ))
        #expect(noAmount.isError)

        let badType = await registry.execute(LLMToolCall(
            id: "t2", name: "add_transaction",
            input: ["title": "Coffee", "amount": 5, "type": "transfer", "category": "food"]
        ))
        #expect(badType.isError)

        // Unknown category degrades to .other instead of failing.
        let odd = await registry.execute(LLMToolCall(
            id: "t3", name: "add_transaction",
            input: ["title": "Mystery", "amount": 5, "type": "expense", "category": "weird"]
        ))
        #expect(!odd.isError)
        #expect(store.transactions[0].category == .other)
    }

    @Test func financeSummaryToolIsSilentAndLimited() async throws {
        let (store, _) = try makeStore()
        for index in 0..<8 {
            try await store.add(tx("t\(index)", "Item \(index)", 10))
        }
        try await store.add(tx("inc", "Salary", 1000, type: .income, category: .salary))
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(id: "t1", name: "get_finance_summary", input: ["limit": 3])
        let result = await registry.execute(call)
        let json = JSONValue.decoded(from: result.content)

        #expect(json?["income"]?.doubleValue == 1000)
        #expect(json?["expenses"]?.doubleValue == 80)
        #expect(json?["balance"]?.doubleValue == 920)
        #expect(json?["count"]?.intValue == 9)
        #expect(json?["recent"]?.arrayValue?.count == 3)
        #expect(json?["recent"]?[0]?["title"]?.stringValue == "Salary")
        #expect(registry.confirmation(for: call) == nil)
    }

    @Test func toolsAreScopedToFinanceSphere() throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)
        #expect(
            registry.toolsFor(.finance).map(\.name).sorted()
                == ["add_transaction", "get_finance_summary"]
        )
        #expect(registry.toolsFor(.goals).isEmpty)
    }
}

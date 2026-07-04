import Foundation
import Testing
@testable import SphereCore

@Suite("FinanceMath: safe to spend")
struct FinanceMathTests {
    private let cal = Calendar.current
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func nilWhenNoBudget() {
        #expect(FinanceMath.safeToSpendToday(budgetTotal: 0, spentThisMonth: 0, committed: 0) == nil)
    }

    @Test func dividesRemainingOverDaysLeft() {
        // July has 31 days; on the 24th there are 8 days left (24..31).
        let now = date(2026, 7, 24)
        #expect(FinanceMath.daysLeftInMonth(asOf: now) == 8)
        // 1000 budget − 200 spent − 40 committed = 760 over 8 days = 95/day.
        let safe = FinanceMath.safeToSpendToday(
            budgetTotal: 1000, spentThisMonth: 200, committed: 40, asOf: now
        )
        #expect(safe == 95)
    }

    @Test func neverNegative() {
        let now = date(2026, 7, 15)
        let safe = FinanceMath.safeToSpendToday(
            budgetTotal: 100, spentThisMonth: 500, committed: 0, asOf: now
        )
        #expect(safe == 0)
    }
}

@Suite("Finance extras: debts, investments, wishlist, net worth")
@MainActor
struct FinanceExtrasTests {
    private func makeStore() throws -> (FinanceStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (FinanceStore(database: database), database)
    }

    @Test func netWorthCombinesAccountsInvestmentsDebts() async throws {
        let (store, database) = try makeStore()
        try await store.load()
        try await store.addAccount(Account(id: "a", name: "Checking", type: .checking, balance: 1000))
        try await store.addInvestment(Investment(id: "i", name: "Index", type: .fund, value: 500))
        try await store.addDebt(Debt(id: "d", name: "Loan", totalAmount: 1000, remaining: 300))

        #expect(store.netWorth == 1200) // 1000 + 500 − 300
        #expect(store.totalDebt == 300)

        let reloaded = FinanceStore(database: database)
        try await reloaded.load()
        #expect(reloaded.debts.count == 1)
        #expect(reloaded.investments.count == 1)
    }

    @Test func debtProgressFraction() {
        let debt = Debt(id: "d", name: "Car", totalAmount: 2000, remaining: 500)
        #expect(abs(debt.progress - 0.75) < 0.0001)
    }

    @Test func wishlistCoolingOff() async throws {
        let (store, _) = try makeStore()
        try await store.load()
        let now = Date()
        let old = WishlistItem(id: "w1", title: "Headphones", amount: 200,
                               createdAt: now.addingTimeInterval(-73 * 3600))
        let fresh = WishlistItem(id: "w2", title: "Jacket", amount: 150, createdAt: now)
        try await store.addWishlistItem(old)
        try await store.addWishlistItem(fresh)

        #expect(old.isRipe(asOf: now))
        #expect(!fresh.isRipe(asOf: now))
        #expect(fresh.hoursUntilRipe(asOf: now) == 72)
        #expect(store.wishlist.count == 2)
    }

    @Test func upcomingRenewalsSortedByDaysLeft() async throws {
        let (store, _) = try makeStore()
        try await store.load()
        let today = Calendar.current.component(.day, from: Date())
        let soon = (today % 28) + 1
        try await store.addSubscription(Subscription(id: "s1", name: "Netflix", amount: 12, billingDay: soon))
        let renewals = store.upcomingRenewals(within: 31)
        #expect(renewals.contains { $0.id == "s1" })
    }
}

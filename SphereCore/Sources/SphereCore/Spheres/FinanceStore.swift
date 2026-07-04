import Foundation
import GRDB
import Observation

/// Finance sphere store: transactions feed, per-category monthly budgets,
/// and subscriptions. Follows the golden-template shape (docs/HANDOFF.md).
@MainActor
@Observable
public final class FinanceStore {
    /// Newest first, matching the feed order.
    public private(set) var transactions: [Transaction] = []
    public private(set) var budgets: [Budget] = []
    public private(set) var subscriptions: [Subscription] = []
    public private(set) var accounts: [Account] = []
    public private(set) var savingsGoals: [SavingsGoal] = []
    public private(set) var debts: [Debt] = []
    public private(set) var investments: [Investment] = []
    public private(set) var wishlist: [WishlistItem] = []

    private let database: AppDatabase
    private let engram: EngramStore?

    public init(database: AppDatabase, engram: EngramStore? = nil) {
        self.database = database
        self.engram = engram
    }

    public func load() async throws {
        let (transactions, budgets, subscriptions, accounts, savings, debts, investments, wishlist) =
            try await database.writer.read { db in
                (
                    try Transaction.fetchAll(db, sql: "SELECT * FROM transactions ORDER BY date DESC, rowid DESC"),
                    try Budget.fetchAll(db),
                    try Subscription.fetchAll(db),
                    try Account.fetchAll(db),
                    try SavingsGoal.fetchAll(db),
                    try Debt.fetchAll(db),
                    try Investment.fetchAll(db),
                    try WishlistItem.fetchAll(db, sql: "SELECT * FROM wishlist ORDER BY createdAt DESC")
                )
            }
        self.transactions = transactions
        self.budgets = budgets
        self.subscriptions = subscriptions
        self.accounts = accounts
        self.savingsGoals = savings
        self.debts = debts
        self.investments = investments
        self.wishlist = wishlist
    }

    // MARK: - Transactions

    public func add(_ transaction: Transaction) async throws {
        try await database.writer.write { db in try transaction.insert(db) }
        transactions.insert(transaction, at: 0)
        engram?.note(
            agentId: SphereType.finance.rawValue,
            content: "Logged \(transaction.type.rawValue) \(Int(transaction.amount.rounded())): "
                + "\(transaction.title) (\(transaction.category.rawValue))",
            tags: ["log", "finance", "transaction"]
        )
    }

    public func remove(id: String) async throws {
        _ = try await database.writer.write { db in try Transaction.deleteOne(db, key: id) }
        transactions.removeAll { $0.id == id }
    }

    public var totalIncome: Double {
        transactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }

    public var totalExpenses: Double {
        transactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    public var balance: Double {
        totalIncome - totalExpenses
    }

    // MARK: - Budgets

    public func setBudget(category: TransactionCategory, limit: Double) async throws {
        let budget = Budget(category: category, limit: limit)
        try await database.writer.write { db in try budget.save(db) }
        budgets.removeAll { $0.category == category }
        budgets.append(budget)
    }

    public func removeBudget(id: String) async throws {
        _ = try await database.writer.write { db in try Budget.deleteOne(db, key: id) }
        budgets.removeAll { $0.id == id }
    }

    /// Expenses in `category` during the calendar month containing `now`.
    public func spentThisMonth(
        in category: TransactionCategory,
        asOf now: Date = Date()
    ) -> Double {
        let calendar = Calendar.current
        guard let month = calendar.dateInterval(of: .month, for: now) else { return 0 }
        return transactions
            .filter {
                $0.type == .expense && $0.category == category
                    && $0.date >= month.start && $0.date < month.end
            }
            .reduce(0) { $0 + $1.amount }
    }

    /// Budgets whose category spending exceeds the limit this month.
    public func overBudget(asOf now: Date = Date()) -> [Budget] {
        budgets.filter { spentThisMonth(in: $0.category, asOf: now) > $0.limit }
    }

    // MARK: - Subscriptions

    public func addSubscription(_ subscription: Subscription) async throws {
        try await database.writer.write { db in try subscription.insert(db) }
        subscriptions.append(subscription)
    }

    public func toggleSubscription(id: String) async throws {
        guard var subscription = subscriptions.first(where: { $0.id == id }) else { return }
        subscription.isActive.toggle()
        try await database.writer.write { [subscription] db in try subscription.save(db) }
        subscriptions = subscriptions.map { $0.id == id ? subscription : $0 }
    }

    public func removeSubscription(id: String) async throws {
        _ = try await database.writer.write { db in try Subscription.deleteOne(db, key: id) }
        subscriptions.removeAll { $0.id == id }
    }

    public var totalMonthlySubscriptions: Double {
        subscriptions.filter(\.isActive).reduce(0) { $0 + $1.amount }
    }

    // MARK: - Accounts

    public func addAccount(_ account: Account) async throws {
        try await database.writer.write { db in try account.insert(db) }
        accounts.append(account)
    }

    public func updateAccount(_ account: Account) async throws {
        try await database.writer.write { db in try account.save(db) }
        accounts = accounts.map { $0.id == account.id ? account : $0 }
    }

    public func removeAccount(id: String) async throws {
        _ = try await database.writer.write { db in try Account.deleteOne(db, key: id) }
        accounts.removeAll { $0.id == id }
    }

    /// Sum of all account balances (the net-worth line).
    public var totalAccountBalance: Double {
        accounts.reduce(0) { $0 + $1.balance }
    }

    // MARK: - Savings goals

    public func addSavingsGoal(_ goal: SavingsGoal) async throws {
        try await database.writer.write { db in try goal.insert(db) }
        savingsGoals.append(goal)
        engram?.note(
            agentId: SphereType.finance.rawValue,
            content: "New savings goal: \(goal.name) (target \(Int(goal.target.rounded())))",
            tags: ["log", "finance", "savings"]
        )
    }

    public func removeSavingsGoal(id: String) async throws {
        _ = try await database.writer.write { db in try SavingsGoal.deleteOne(db, key: id) }
        savingsGoals.removeAll { $0.id == id }
    }

    /// Adds (or, with a negative amount, withdraws) toward a goal, never below 0.
    public func addToSavings(id: String, amount: Double) async throws {
        guard var goal = savingsGoals.first(where: { $0.id == id }) else { return }
        goal.saved = max(goal.saved + amount, 0)
        try await database.writer.write { [goal] db in try goal.save(db) }
        savingsGoals = savingsGoals.map { $0.id == id ? goal : $0 }
    }

    // MARK: - Debts

    public func addDebt(_ debt: Debt) async throws {
        try await database.writer.write { db in try debt.insert(db) }
        debts.append(debt)
    }

    public func removeDebt(id: String) async throws {
        _ = try await database.writer.write { db in try Debt.deleteOne(db, key: id) }
        debts.removeAll { $0.id == id }
    }

    public var totalDebt: Double { debts.reduce(0) { $0 + $1.remaining } }

    // MARK: - Investments

    public func addInvestment(_ investment: Investment) async throws {
        try await database.writer.write { db in try investment.insert(db) }
        investments.append(investment)
    }

    public func removeInvestment(id: String) async throws {
        _ = try await database.writer.write { db in try Investment.deleteOne(db, key: id) }
        investments.removeAll { $0.id == id }
    }

    public var totalInvestments: Double { investments.reduce(0) { $0 + $1.value } }

    // MARK: - Wishlist (72h cooling-off)

    public func addWishlistItem(_ item: WishlistItem) async throws {
        try await database.writer.write { db in try item.insert(db) }
        wishlist.insert(item, at: 0)
    }

    public func removeWishlistItem(id: String) async throws {
        _ = try await database.writer.write { db in try WishlistItem.deleteOne(db, key: id) }
        wishlist.removeAll { $0.id == id }
    }

    // MARK: - Insights (gems)

    /// Net worth = accounts + investments − debts.
    public var netWorth: Double {
        totalAccountBalance + totalInvestments - totalDebt
    }

    public var monthlyBudgetTotal: Double {
        budgets.reduce(0) { $0 + $1.limit }
    }

    public func spentThisMonthTotal(asOf now: Date = Date()) -> Double {
        let calendar = Calendar.current
        guard let month = calendar.dateInterval(of: .month, for: now) else { return 0 }
        return transactions
            .filter { $0.type == .expense && $0.date >= month.start && $0.date < month.end }
            .reduce(0) { $0 + $1.amount }
    }

    /// Discretionary money you can spend today (nil until budgets are set).
    public func safeToSpendToday(asOf now: Date = Date()) -> Double? {
        FinanceMath.safeToSpendToday(
            budgetTotal: monthlyBudgetTotal,
            spentThisMonth: spentThisMonthTotal(asOf: now),
            committed: totalMonthlySubscriptions,
            asOf: now
        )
    }

    /// Active subscriptions billing within `days` — the "renewing soon" radar.
    public func upcomingRenewals(within days: Int = 7, asOf now: Date = Date()) -> [Subscription] {
        subscriptions
            .filter { $0.isActive && $0.daysUntilBilling(asOf: now) <= days }
            .sorted { $0.daysUntilBilling(asOf: now) < $1.daysUntilBilling(asOf: now) }
    }

    /// This month's expense totals per category, largest first (non-zero only).
    public func categorySpendingThisMonth(asOf now: Date = Date()) -> [(TransactionCategory, Double)] {
        TransactionCategory.allCases
            .map { ($0, spentThisMonth(in: $0, asOf: now)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    // MARK: - Agent tools

    public nonisolated var tools: [SphereTool] {
        [
            SphereTool(
                definition: LLMTool(
                    name: "add_transaction",
                    description: "Record an income or expense transaction in the finance "
                        + "sphere. Use when the user mentions money spent, received, or a "
                        + "recurring payment.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string", "description": "Short title, e.g. \"Coffee\""],
                            "amount": [
                                "type": "number", "minimum": 0.01,
                                "description": "Amount in the user's currency",
                            ],
                            "type": [
                                "type": "string",
                                "enum": ["income", "expense"],
                                "description": "income or expense",
                            ],
                            "category": [
                                "type": "string",
                                "enum": [
                                    "food", "transport", "shopping", "health", "entertainment",
                                    "housing", "salary", "freelance", "investment", "other",
                                ],
                            ],
                            "note": ["type": "string", "description": "Optional extra detail"],
                        ],
                        "required": ["title", "amount", "type", "category"],
                    ]
                ),
                spheres: [.finance],
                confirmation: { input in
                    let verb = input["type"]?.stringValue == "income" ? "Logged income" : "Logged expense"
                    let amount = input["amount"]?.doubleValue.map { String(format: "%g", $0) } ?? "?"
                    let title = input["title"]?.stringValue ?? ""
                    let category = input["category"]?.stringValue ?? ""
                    return "\(verb) \(amount) — \(title)\(category.isEmpty ? "" : " (\(category))")"
                },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let title = input["title"]?.stringValue, !title.isEmpty else {
                        throw AgentToolInputError("title is required")
                    }
                    guard let amount = input["amount"]?.doubleValue, amount > 0 else {
                        throw AgentToolInputError("amount must be a positive number")
                    }
                    guard let type = input["type"]?.stringValue.flatMap(TransactionType.init(rawValue:)) else {
                        throw AgentToolInputError("type must be income or expense")
                    }
                    let category = input["category"]?.stringValue
                        .flatMap(TransactionCategory.init(rawValue:)) ?? .other
                    let transaction = Transaction(
                        id: Transaction.newID(),
                        title: title,
                        amount: amount,
                        type: type,
                        category: category,
                        date: Date(),
                        note: input["note"]?.stringValue ?? ""
                    )
                    try await self.add(transaction)
                    return JSONValue.object(["ok": true, "id": .string(transaction.id)]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "get_finance_summary",
                    description: "Look up the user's current finances: total income, expenses, "
                        + "balance, and the most recent transactions. Use before answering "
                        + "questions about spending or money.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "limit": [
                                "type": "integer", "minimum": 1, "maximum": 20,
                                "description": "How many recent transactions (default 5)",
                            ],
                        ],
                        "required": [],
                    ]
                ),
                spheres: [.finance],
                silent: true,
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    let limit = input["limit"]?.intValue ?? 5
                    return await self.financeSummaryJSON(limit: limit)
                }
            ),
        ]
    }

    private func financeSummaryJSON(limit: Int) -> String {
        var summary: [String: JSONValue] = [
            "income": .number(totalIncome),
            "expenses": .number(totalExpenses),
            "balance": .number(balance),
            "count": .number(Double(transactions.count)),
            "recent": .array(transactions.prefix(limit).map { transaction in
                .object([
                    "title": .string(transaction.title),
                    "amount": .number(transaction.amount),
                    "type": .string(transaction.type.rawValue),
                    "category": .string(transaction.category.rawValue),
                    "date": .string(DayKey.make(transaction.date)),
                ])
            }),
        ]
        if !accounts.isEmpty {
            summary["totalAccountBalance"] = .number(totalAccountBalance)
        }
        if let safe = safeToSpendToday() {
            summary["safeToSpendToday"] = .number((safe * 100).rounded() / 100)
        }
        if !debts.isEmpty || !investments.isEmpty {
            summary["netWorth"] = .number((netWorth * 100).rounded() / 100)
            if !debts.isEmpty { summary["totalDebt"] = .number(totalDebt) }
            if !investments.isEmpty { summary["totalInvestments"] = .number(totalInvestments) }
        }
        if !savingsGoals.isEmpty {
            summary["savingsGoals"] = .array(savingsGoals.map { goal in
                .object([
                    "name": .string(goal.name),
                    "saved": .number(goal.saved),
                    "target": .number(goal.target),
                    "percent": .number((goal.percent * 100).rounded()),
                ])
            })
        }
        return JSONValue.object(summary).encodedString()
    }
}

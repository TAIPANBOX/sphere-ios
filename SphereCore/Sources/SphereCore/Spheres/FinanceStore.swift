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

    private let database: AppDatabase
    private let engram: EngramStore?

    public init(database: AppDatabase, engram: EngramStore? = nil) {
        self.database = database
        self.engram = engram
    }

    public func load() async throws {
        let (transactions, budgets, subscriptions) = try await database.writer.read { db in
            (
                try Transaction.fetchAll(db, sql: "SELECT * FROM transactions ORDER BY date DESC, rowid DESC"),
                try Budget.fetchAll(db),
                try Subscription.fetchAll(db)
            )
        }
        self.transactions = transactions
        self.budgets = budgets
        self.subscriptions = subscriptions
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
        JSONValue.object([
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
        ]).encodedString()
    }
}

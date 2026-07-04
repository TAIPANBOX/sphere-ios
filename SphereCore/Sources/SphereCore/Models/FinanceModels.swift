import Foundation
import GRDB

public enum TransactionType: String, Codable, CaseIterable, Sendable {
    case income
    case expense
}

public enum TransactionCategory: String, Codable, CaseIterable, Sendable {
    case food, transport, shopping, health, entertainment
    case housing, salary, freelance, investment, other

    public var label: String {
        switch self {
        case .food: "Food"
        case .transport: "Transport"
        case .shopping: "Shopping"
        case .health: "Health"
        case .entertainment: "Entertainment"
        case .housing: "Housing"
        case .salary: "Salary"
        case .freelance: "Freelance"
        case .investment: "Investment"
        case .other: "Other"
        }
    }

    public var emoji: String {
        switch self {
        case .food: "🍔"
        case .transport: "🚗"
        case .shopping: "🛍️"
        case .health: "💊"
        case .entertainment: "🎬"
        case .housing: "🏠"
        case .salary: "💼"
        case .freelance: "💻"
        case .investment: "📈"
        case .other: "💳"
        }
    }
}

public struct Transaction: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var amount: Double
    public var type: TransactionType
    public var category: TransactionCategory
    public var date: Date
    public var note: String

    public init(
        id: String,
        title: String,
        amount: Double,
        type: TransactionType,
        category: TransactionCategory,
        date: Date,
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.type = type
        self.category = category
        self.date = date
        self.note = note
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("tx", now: now)
    }
}

extension Transaction: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "transactions"
}

/// Per-category monthly spending limit. One budget per category
/// (`id == category.rawValue`).
public struct Budget: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var category: TransactionCategory
    public var limit: Double

    public init(category: TransactionCategory, limit: Double) {
        self.id = category.rawValue
        self.category = category
        self.limit = limit
    }
}

extension Budget: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "budgets"
}

public struct Subscription: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    public var amount: Double
    /// Day of month (1–31) the subscription bills.
    public var billingDay: Int
    public var isActive: Bool

    public init(
        id: String,
        name: String,
        emoji: String = "📱",
        amount: Double,
        billingDay: Int,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.amount = amount
        self.billingDay = billingDay
        self.isActive = isActive
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("sub", now: now)
    }

    public func daysUntilBilling(asOf now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var parts = calendar.dateComponents([.year, .month], from: today)
        parts.day = billingDay
        guard var next = calendar.date(from: parts) else { return 0 }
        if next < today {
            next = calendar.date(byAdding: .month, value: 1, to: next) ?? next
        }
        return calendar.dateComponents([.day], from: today, to: next).day ?? 0
    }
}

extension Subscription: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "subscriptions"
}

public enum AccountType: String, Codable, CaseIterable, Sendable {
    case checking, savings, cash, crypto, other

    public var label: String {
        switch self {
        case .checking: "Checking"
        case .savings: "Savings"
        case .cash: "Cash"
        case .crypto: "Crypto"
        case .other: "Other"
        }
    }

    public var emoji: String {
        switch self {
        case .checking: "🏦"
        case .savings: "🐖"
        case .cash: "💵"
        case .crypto: "₿"
        case .other: "💳"
        }
    }
}

public struct Account: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var type: AccountType
    public var balance: Double
    public var note: String

    public init(
        id: String,
        name: String,
        type: AccountType = .checking,
        balance: Double = 0,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.balance = balance
        self.note = note
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("acct", now: now)
    }
}

extension Account: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "accounts"
}

public struct SavingsGoal: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    public var target: Double
    public var saved: Double

    public init(
        id: String,
        name: String,
        emoji: String = "🎯",
        target: Double,
        saved: Double = 0
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.target = target
        self.saved = saved
    }

    /// 0–1
    public var percent: Double {
        target > 0 ? min(max(saved / target, 0), 1) : 0
    }

    public var remaining: Double {
        min(max(target - saved, 0), target)
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("save", now: now)
    }
}

extension SavingsGoal: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "savings_goals"
}

// MARK: - finance-v3 (debts, investments, wishlist)

public struct Debt: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var lender: String
    public var totalAmount: Double
    public var remaining: Double
    public var monthlyPayment: Double
    public var note: String

    public init(
        id: String, name: String, lender: String = "",
        totalAmount: Double, remaining: Double, monthlyPayment: Double = 0, note: String = ""
    ) {
        self.id = id
        self.name = name
        self.lender = lender
        self.totalAmount = totalAmount
        self.remaining = remaining
        self.monthlyPayment = monthlyPayment
        self.note = note
    }

    /// 0–1 fraction paid off.
    public var progress: Double {
        totalAmount > 0 ? max(0, min((totalAmount - remaining) / totalAmount, 1)) : 0
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("debt", now: now) }
}

extension Debt: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "debts"
}

public enum InvestmentType: String, Codable, CaseIterable, Sendable {
    case stocks, crypto, bonds, realEstate, fund, other

    public var label: String {
        switch self {
        case .stocks: "Stocks"
        case .crypto: "Crypto"
        case .bonds: "Bonds"
        case .realEstate: "Real estate"
        case .fund: "Fund"
        case .other: "Other"
        }
    }
}

public struct Investment: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var type: InvestmentType
    public var value: Double
    public var note: String

    public init(
        id: String, name: String, type: InvestmentType = .other, value: Double, note: String = ""
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.value = value
        self.note = note
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("invest", now: now) }
}

extension Investment: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "investments"
}

/// A considered purchase held for a cooling-off period before it becomes a
/// "decide now" prompt — curbs impulse spending.
public struct WishlistItem: Codable, Equatable, Identifiable, Sendable {
    public static let coolingHours = 72

    public var id: String
    public var title: String
    public var amount: Double
    public var createdAt: Date
    public var note: String

    public init(id: String, title: String, amount: Double, createdAt: Date, note: String = "") {
        self.id = id
        self.title = title
        self.amount = amount
        self.createdAt = createdAt
        self.note = note
    }

    /// True once the 72-hour cooling-off has elapsed — time to buy or drop it.
    public func isRipe(asOf now: Date = Date()) -> Bool {
        now.timeIntervalSince(createdAt) >= Double(Self.coolingHours) * 3600
    }

    /// Whole hours remaining before it ripens (0 once ripe).
    public func hoursUntilRipe(asOf now: Date = Date()) -> Int {
        let remaining = Double(Self.coolingHours) * 3600 - now.timeIntervalSince(createdAt)
        return max(Int((remaining / 3600).rounded(.up)), 0)
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("wish", now: now) }
}

extension WishlistItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "wishlist"
}

/// Pure discretionary-budget math for the "safe to spend today" number.
public enum FinanceMath {
    /// Days remaining in the current month, including today (≥ 1).
    public static func daysLeftInMonth(asOf now: Date = Date()) -> Int {
        let calendar = Calendar.current
        guard let month = calendar.dateInterval(of: .month, for: now) else { return 1 }
        let today = calendar.startOfDay(for: now)
        let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end) ?? today
        let diff = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: lastDay)).day ?? 0
        return max(diff + 1, 1)
    }

    /// Discretionary money left for the rest of the month, spread over the days
    /// remaining. Nil when the user has set no budgets (nothing to divide).
    public static func safeToSpendToday(
        budgetTotal: Double, spentThisMonth: Double, committed: Double, asOf now: Date = Date()
    ) -> Double? {
        guard budgetTotal > 0 else { return nil }
        let remaining = max(budgetTotal - spentThisMonth - committed, 0)
        return remaining / Double(daysLeftInMonth(asOf: now))
    }
}

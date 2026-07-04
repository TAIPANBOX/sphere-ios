import Foundation
import GRDB

public enum HomeCategory: String, Codable, CaseIterable, Sendable {
    case cleaning, repair, organization, garden, shopping, bills, other

    public var label: String {
        switch self {
        case .cleaning: "Cleaning"
        case .repair: "Repair"
        case .organization: "Organization"
        case .garden: "Garden"
        case .shopping: "Shopping"
        case .bills: "Bills"
        case .other: "Other"
        }
    }

    public var emoji: String {
        switch self {
        case .cleaning: "🧹"
        case .repair: "🔧"
        case .organization: "📦"
        case .garden: "🌱"
        case .shopping: "🛒"
        case .bills: "📄"
        case .other: "🏠"
        }
    }
}

public enum HomeTaskStatus: String, Codable, CaseIterable, Sendable {
    case todo, done
}

public struct HomeTask: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var category: HomeCategory
    public var status: HomeTaskStatus
    public var dueDate: Date?
    public var isRecurring: Bool
    /// Days between recurrences (0 = one-off). Drives respawn on completion.
    public var recurrenceDays: Int
    public var createdAt: Date

    public init(
        id: String,
        title: String,
        category: HomeCategory = .other,
        status: HomeTaskStatus = .todo,
        dueDate: Date? = nil,
        isRecurring: Bool = false,
        recurrenceDays: Int = 0,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.status = status
        self.dueDate = dueDate
        self.isRecurring = isRecurring
        self.recurrenceDays = recurrenceDays
        self.createdAt = createdAt
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("hometask", now: now)
    }
}

extension HomeTask: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "home_tasks"
}

public struct Plant: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    public var lastWatered: Date?
    public var intervalDays: Int

    public init(
        id: String,
        name: String,
        emoji: String = "🌿",
        lastWatered: Date? = nil,
        intervalDays: Int = 3
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.lastWatered = lastWatered
        self.intervalDays = intervalDays
    }

    public func needsWatering(asOf now: Date = Date()) -> Bool {
        guard let lastWatered else { return true }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: lastWatered),
            to: Calendar.current.startOfDay(for: now)
        ).day ?? 0
        return days >= intervalDays
    }

    public func daysUntilWatering(asOf now: Date = Date()) -> Int {
        guard let lastWatered else { return 0 }
        let due = lastWatered.addingTimeInterval(Double(intervalDays) * 86_400)
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: now),
            to: Calendar.current.startOfDay(for: due)
        ).day ?? 0
        return max(days, 0)
    }

    public func watered(on date: Date = Date()) -> Plant {
        var copy = self
        copy.lastWatered = date
        return copy
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("plant", now: now)
    }
}

extension Plant: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "plants"
}

public struct ShoppingItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var category: String
    public var checked: Bool

    public init(id: String, name: String, category: String = "General", checked: Bool = false) {
        self.id = id
        self.name = name
        self.category = category
        self.checked = checked
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("shop", now: now)
    }
}

extension ShoppingItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "shopping_items"
}

// MARK: - home-v2 (appliances, utilities, renovation, inventory)

public struct Appliance: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var brand: String
    public var purchaseDate: Date?
    public var warrantyUntil: Date?
    public var note: String

    public init(
        id: String, name: String, brand: String = "",
        purchaseDate: Date? = nil, warrantyUntil: Date? = nil, note: String = ""
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.purchaseDate = purchaseDate
        self.warrantyUntil = warrantyUntil
        self.note = note
    }

    /// Days until the warranty lapses (nil if none; negative once expired).
    public func warrantyDaysLeft(asOf now: Date = Date()) -> Int? {
        guard let warrantyUntil else { return nil }
        return DayKey.calendar.dateComponents(
            [.day], from: DayKey.calendar.startOfDay(for: now),
            to: DayKey.calendar.startOfDay(for: warrantyUntil)
        ).day
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("appliance", now: now) }
}

extension Appliance: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "appliances"
}

public enum UtilityKind: String, Codable, CaseIterable, Sendable {
    case electricity, water, gas, internet, other

    public var emoji: String {
        switch self {
        case .electricity: "⚡"
        case .water: "💧"
        case .gas: "🔥"
        case .internet: "🌐"
        case .other: "🧾"
        }
    }
}

public struct UtilityReading: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: UtilityKind
    public var value: Double
    public var cost: Double
    public var date: Date
    public var note: String

    public init(
        id: String, kind: UtilityKind, value: Double, cost: Double = 0,
        date: Date, note: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.cost = cost
        self.date = date
        self.note = note
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("utility", now: now) }
}

extension UtilityReading: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "utility_readings"
}

public enum RenovationStatus: String, Codable, CaseIterable, Sendable {
    case planning, inProgress, done

    public var label: String {
        switch self {
        case .planning: "Planning"
        case .inProgress: "In progress"
        case .done: "Done"
        }
    }
}

public struct RenovationProject: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var status: RenovationStatus
    public var budget: Double
    public var spent: Double
    public var note: String

    public init(
        id: String, name: String, status: RenovationStatus = .planning,
        budget: Double = 0, spent: Double = 0, note: String = ""
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.budget = budget
        self.spent = spent
        self.note = note
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("renovation", now: now) }
}

extension RenovationProject: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "renovation_projects"
}

/// A household item, optionally lent to someone ("who did I lend this to").
public struct InventoryItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var quantity: Int
    public var location: String
    public var lentTo: String
    public var note: String

    public init(
        id: String, name: String, quantity: Int = 1,
        location: String = "", lentTo: String = "", note: String = ""
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.location = location
        self.lentTo = lentTo
        self.note = note
    }

    public var isLentOut: Bool { !lentTo.trimmingCharacters(in: .whitespaces).isEmpty }

    public static func newID(now: Date = Date()) -> String { EntityID.make("inventory", now: now) }
}

extension InventoryItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "inventory_items"
}

/// Recurring/degrading-chore respawn: a completed recurring task spawns its
/// next occurrence with the due date advanced by its interval.
public enum RecurringChore {
    public static func nextOccurrence(after task: HomeTask, completedAt now: Date = Date()) -> HomeTask? {
        guard task.isRecurring, task.recurrenceDays > 0 else { return nil }
        let base = task.dueDate ?? now
        let next = DayKey.calendar.date(byAdding: .day, value: task.recurrenceDays, to: base) ?? now
        return HomeTask(
            id: HomeTask.newID(now: now), title: task.title, category: task.category,
            status: .todo, dueDate: next, isRecurring: true,
            recurrenceDays: task.recurrenceDays, createdAt: now
        )
    }
}

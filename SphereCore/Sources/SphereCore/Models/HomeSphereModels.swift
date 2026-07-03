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
    public var createdAt: Date

    public init(
        id: String,
        title: String,
        category: HomeCategory = .other,
        status: HomeTaskStatus = .todo,
        dueDate: Date? = nil,
        isRecurring: Bool = false,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.status = status
        self.dueDate = dueDate
        self.isRecurring = isRecurring
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

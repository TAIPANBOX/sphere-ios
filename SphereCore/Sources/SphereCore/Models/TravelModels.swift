import Foundation
import GRDB

public enum TravelStatus: String, Codable, CaseIterable, Sendable {
    case planned, booked, completed, cancelled
}

public enum TravelType: String, Codable, CaseIterable, Sendable {
    case city, beach, mountain, culture, adventure, business, other

    public var label: String {
        switch self {
        case .city: "City Break"
        case .beach: "Beach"
        case .mountain: "Mountain"
        case .culture: "Culture"
        case .adventure: "Adventure"
        case .business: "Business"
        case .other: "Other"
        }
    }

    public var emoji: String {
        switch self {
        case .city: "🏙️"
        case .beach: "🏖️"
        case .mountain: "🏔️"
        case .culture: "🏛️"
        case .adventure: "🧗"
        case .business: "💼"
        case .other: "✈️"
        }
    }
}

public struct TravelPlan: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var destination: String
    public var country: String
    public var emoji: String
    public var type: TravelType
    public var status: TravelStatus
    public var startDate: Date?
    public var endDate: Date?
    public var notes: String
    public var budget: Double
    public var packingList: [String: Bool]
    public var documents: [String: Bool]

    public init(
        id: String,
        destination: String,
        country: String = "",
        emoji: String = "✈️",
        type: TravelType = .city,
        status: TravelStatus = .planned,
        startDate: Date? = nil,
        endDate: Date? = nil,
        notes: String = "",
        budget: Double = 0,
        packingList: [String: Bool] = [:],
        documents: [String: Bool] = [:]
    ) {
        self.id = id
        self.destination = destination
        self.country = country
        self.emoji = emoji
        self.type = type
        self.status = status
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.budget = budget
        self.packingList = packingList
        self.documents = documents
    }

    public static func newID(now: Date = Date()) -> String {
        "trip_\(Int64(now.timeIntervalSince1970 * 1000))"
    }

    /// Days until the start date; nil when unscheduled or already started.
    public func daysUntil(asOf now: Date = Date()) -> Int? {
        guard let startDate else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: startDate)
        ).day ?? 0
        return days >= 0 ? days : nil
    }

    public static func defaultPacking(for type: TravelType) -> [String: Bool] {
        var base = [
            "Passport": false, "Phone charger": false, "Medications": false,
            "Cash/cards": false, "Clothes": false, "Toiletries": false,
        ]
        switch type {
        case .beach:
            base["Sunscreen"] = false
            base["Swimwear"] = false
            base["Beach towel"] = false
        case .mountain, .adventure:
            base["Hiking boots"] = false
            base["Rain jacket"] = false
            base["First aid kit"] = false
        case .business:
            base["Laptop"] = false
            base["Business cards"] = false
            base["Formal clothes"] = false
        default:
            break
        }
        return base
    }

    public static let defaultDocuments: [String: Bool] = [
        "Passport": false,
        "Visa (if required)": false,
        "Travel insurance": false,
        "Flight tickets": false,
        "Hotel booking": false,
        "Emergency contacts": false,
    ]
}

extension TravelPlan: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "travel_plans"
}

public struct VisitedCountry: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var flag: String
    public var year: Int?

    public var id: String { name }

    public init(name: String, flag: String, year: Int? = nil) {
        self.name = name
        self.flag = flag
        self.year = year
    }
}

extension VisitedCountry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "visited_countries"
}

public struct WishlistDestination: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var destination: String
    public var country: String
    public var flag: String
    public var note: String

    public init(id: String, destination: String, country: String, flag: String, note: String = "") {
        self.id = id
        self.destination = destination
        self.country = country
        self.flag = flag
        self.note = note
    }

    public static func newID(now: Date = Date()) -> String {
        "wish_\(Int64(now.timeIntervalSince1970 * 1000))"
    }
}

extension WishlistDestination: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "wishlist_destinations"
}

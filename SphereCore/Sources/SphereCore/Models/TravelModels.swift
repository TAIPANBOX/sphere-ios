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
    public var spent: Double
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
        spent: Double = 0,
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
        self.spent = spent
        self.packingList = packingList
        self.documents = documents
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("trip", now: now)
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
        EntityID.make("wish", now: now)
    }
}

extension WishlistDestination: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "wishlist_destinations"
}

// MARK: - travel-v2 (journal, jet-lag, country guide)

public struct TripJournalEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var tripId: String
    public var date: Date
    public var text: String

    public init(id: String, tripId: String, date: Date, text: String) {
        self.id = id
        self.tripId = tripId
        self.date = date
        self.text = text
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("tripnote", now: now) }
}

extension TripJournalEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "trip_journal"
}

public struct JetLagStep: Sendable, Equatable {
    /// Days before departure (1 = the night before).
    public let daysBefore: Int
    public let advice: String

    public init(daysBefore: Int, advice: String) {
        self.daysBefore = daysBefore
        self.advice = advice
    }
}

/// Pre-trip circadian shift: nudge bedtime ~1h/day toward the destination,
/// capped at the actual time difference. Positive `hoursDifference` = the
/// destination is ahead (travelling east → shift earlier); negative = behind
/// (west → later).
public enum JetLagPlan {
    public static func plan(hoursDifference: Int, daysBefore: Int = 3) -> [JetLagStep] {
        guard hoursDifference != 0 else { return [] }
        let direction = hoursDifference > 0 ? "earlier" : "later"
        let maxShift = abs(hoursDifference)
        var steps: [JetLagStep] = []
        for day in stride(from: daysBefore, through: 1, by: -1) {
            let shift = min(daysBefore - day + 1, maxShift)
            steps.append(JetLagStep(
                daysBefore: day,
                advice: "\(day) day\(day == 1 ? "" : "s") before: bed & wake ~\(shift)h \(direction)"
            ))
        }
        return steps
    }
}

/// Emergency and practical basics per country, for the offline trip card.
public struct CountryInfo: Sendable, Equatable {
    public let emergency: String
    public let plug: String
    public let note: String
}

public enum CountryGuide {
    private static let data: [String: CountryInfo] = [
        "ukraine": CountryInfo(emergency: "112", plug: "Type C/F, 230V", note: "Hryvnia (₴)"),
        "usa": CountryInfo(emergency: "911", plug: "Type A/B, 120V", note: "Tip ~18–20%"),
        "united kingdom": CountryInfo(emergency: "999 / 112", plug: "Type G, 230V", note: "Pound (£)"),
        "uk": CountryInfo(emergency: "999 / 112", plug: "Type G, 230V", note: "Pound (£)"),
        "germany": CountryInfo(emergency: "112", plug: "Type C/F, 230V", note: "Euro (€)"),
        "france": CountryInfo(emergency: "112", plug: "Type C/E, 230V", note: "Euro (€)"),
        "spain": CountryInfo(emergency: "112", plug: "Type C/F, 230V", note: "Euro (€)"),
        "italy": CountryInfo(emergency: "112", plug: "Type C/F/L, 230V", note: "Euro (€)"),
        "japan": CountryInfo(emergency: "110 police / 119 fire", plug: "Type A/B, 100V", note: "Cash-friendly"),
        "poland": CountryInfo(emergency: "112", plug: "Type C/E, 230V", note: "Złoty (zł)"),
    ]

    public static func info(for country: String) -> CountryInfo? {
        data[country.lowercased().trimmingCharacters(in: .whitespaces)]
    }
}

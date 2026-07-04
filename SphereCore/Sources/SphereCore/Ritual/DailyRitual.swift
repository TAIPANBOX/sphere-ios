import Foundation
import GRDB

/// One day's open/close ritual — a 2-minute morning plan and an evening
/// review. Sunsama's most-praised feature, generalized across every sphere:
/// the morning sets an intention and commits to today's focus; the evening
/// reflects and "closes the day" for psychological completion. A cross-sphere
/// retention ritual no single-sphere tracker offers.
public struct DailyRitual: Codable, Equatable, Sendable {
    public var dateKey: String
    public var intention: String
    public var plannedFocusIds: [String]
    public var reflection: String
    public var morningCompletedAt: Date?
    public var eveningCompletedAt: Date?

    public init(
        dateKey: String,
        intention: String = "",
        plannedFocusIds: [String] = [],
        reflection: String = "",
        morningCompletedAt: Date? = nil,
        eveningCompletedAt: Date? = nil
    ) {
        self.dateKey = dateKey
        self.intention = intention
        self.plannedFocusIds = plannedFocusIds
        self.reflection = reflection
        self.morningCompletedAt = morningCompletedAt
        self.eveningCompletedAt = eveningCompletedAt
    }

    public var morningDone: Bool { morningCompletedAt != nil }
    public var eveningDone: Bool { eveningCompletedAt != nil }

    public static func empty(for date: Date = Date()) -> DailyRitual {
        DailyRitual(dateKey: DayKey.make(date))
    }
}

extension DailyRitual: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "daily_ritual"
}

public enum RitualPhase: Equatable, Sendable {
    case morning
    case evening
    case none
}

/// Decides which ritual prompt (if any) to surface, from the time of day and
/// what's already been completed today. Pure and testable.
public enum RitualTiming {
    public static func phase(
        ritual: DailyRitual,
        asOf now: Date = Date(),
        morningStartHour: Int = 5,
        eveningStartHour: Int = 18
    ) -> RitualPhase {
        let hour = DayKey.calendar.component(.hour, from: now)
        if hour >= eveningStartHour {
            return ritual.eveningDone ? .none : .evening
        }
        if hour >= morningStartHour {
            return ritual.morningDone ? .none : .morning
        }
        return .none
    }
}

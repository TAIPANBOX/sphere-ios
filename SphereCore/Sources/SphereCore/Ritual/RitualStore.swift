import Foundation
import GRDB
import Observation

/// Persists today's open/close ritual and exposes which prompt to show.
@MainActor
@Observable
public final class RitualStore {
    public private(set) var today: DailyRitual

    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
        self.today = .empty()
    }

    public func load(asOf now: Date = Date()) async throws {
        let key = DayKey.make(now)
        let row = try await database.writer.read { db in
            try DailyRitual.fetchOne(db, key: key)
        }
        today = row ?? .empty(for: now)
    }

    public func phase(asOf now: Date = Date()) -> RitualPhase {
        RitualTiming.phase(ritual: today, asOf: now)
    }

    public func completeMorning(
        intention: String, focusIds: [String], at now: Date = Date()
    ) async throws {
        let updated = DailyRitual(
            dateKey: today.dateKey,
            intention: intention.trimmingCharacters(in: .whitespacesAndNewlines),
            plannedFocusIds: focusIds,
            reflection: today.reflection,
            morningCompletedAt: now,
            eveningCompletedAt: today.eveningCompletedAt
        )
        try await database.writer.write { db in try updated.save(db) }
        today = updated
    }

    public func completeEvening(reflection: String, at now: Date = Date()) async throws {
        let updated = DailyRitual(
            dateKey: today.dateKey,
            intention: today.intention,
            plannedFocusIds: today.plannedFocusIds,
            reflection: reflection.trimmingCharacters(in: .whitespacesAndNewlines),
            morningCompletedAt: today.morningCompletedAt,
            eveningCompletedAt: now
        )
        try await database.writer.write { db in try updated.save(db) }
        today = updated
    }
}

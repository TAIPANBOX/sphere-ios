import Foundation
import GRDB

/// Cross-process quick-log writes for App Intents / interactive widgets, which
/// run in an extension without the full `AppContainer`. These open a
/// short-lived connection to the shared App Group database and write with the
/// same atomic SQL the stores use, so a log from the widget and a log from the
/// app can't lose each other.
public enum QuickLogSQL {
    /// Adds one glass of water atomically (capped), returning the new count.
    @discardableResult
    public static func incrementWater(
        _ writer: any DatabaseWriter, cap: Int = 12, on date: Date = Date()
    ) async throws -> Int {
        let key = DayKey.make(date)
        return try await writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO water (dateKey, glasses) VALUES (?, 1)
                    ON CONFLICT(dateKey) DO UPDATE SET glasses = MIN(glasses + 1, ?)
                    """,
                arguments: [key, cap]
            )
            return try Int.fetchOne(
                db, sql: "SELECT glasses FROM water WHERE dateKey = ?", arguments: [key]
            ) ?? 0
        }
    }

    /// Sets today's mood (1–5), overwriting an earlier check-in.
    public static func setMood(
        _ writer: any DatabaseWriter, score: Int, on date: Date = Date()
    ) async throws {
        let key = DayKey.make(date)
        let clamped = min(max(score, 1), 5)
        try await writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO moods (dateKey, score) VALUES (?, ?)
                    ON CONFLICT(dateKey) DO UPDATE SET score = excluded.score
                    """,
                arguments: [key, clamped]
            )
        }
    }

    /// Logs a breathing meditation of `minutes`.
    public static func addMeditation(
        _ writer: any DatabaseWriter, minutes: Int, on date: Date = Date()
    ) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO meditation_sessions
                        (id, type, durationMinutes, date, note, moodBefore, moodAfter)
                    VALUES (?, ?, ?, ?, '', 3, 4)
                    """,
                arguments: [MeditationSession.newID(now: date), "breathing", max(minutes, 1), date]
            )
        }
    }
}

/// Resolves the shared App Group database URL so extensions can open it
/// directly (the app migrated it there — see the app target's
/// `DatabaseLocation`). Returns nil without the App Group entitlement.
public enum SharedDatabaseLocation {
    public static func databaseURL(
        groupID: String = WidgetSnapshotStore.appGroupID
    ) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("Databases", isDirectory: true)
            .appendingPathComponent("sphere.db")
    }

    /// Opens a short-lived writer on the shared database, or nil if it isn't
    /// there yet (app never launched / no entitlement).
    public static func openWriter() -> (any DatabaseWriter)? {
        guard let url = databaseURL(),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? DatabaseQueue(path: url.path)
    }
}

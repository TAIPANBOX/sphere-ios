import Foundation
import GRDB

/// Sphere domain database (goals, habits, transactions, …) — separate file
/// from the Engram memory DB, same GRDB family. Every sphere adds its tables
/// as a new migration below; migrations run in registration order and must
/// never be edited once shipped.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public convenience init(path: String) throws {
        try self.init(writer: DatabasePool(path: path))
    }

    /// In-memory database for tests and previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    private init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("goals-v1") { db in
            try db.create(table: "goals") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("emoji", .text).notNull().defaults(to: "🎯")
                t.column("horizon", .text).notNull()
                t.column("status", .text).notNull()
                t.column("progressPercent", .integer).notNull().defaults(to: 0)
                t.column("keyResults", .text).notNull().defaults(to: "[]")
                t.column("sphereType", .text)
                t.column("blockedByGoalId", .text)
            }
            try db.create(table: "habits") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("emoji", .text).notNull().defaults(to: "✅")
                t.column("checkInDates", .text).notNull().defaults(to: "[]")
            }
        }

        migrator.registerMigration("health-v1") { db in
            try db.create(table: "water") { t in
                t.primaryKey("dateKey", .text)
                t.column("glasses", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "weights") { t in
                t.primaryKey("dateKey", .text)
                t.column("date", .datetime).notNull()
                t.column("kg", .double).notNull()
            }
            try db.create(table: "workouts") { t in
                t.primaryKey("id", .text)
                t.column("type", .text).notNull()
                t.column("durationMinutes", .integer).notNull()
                t.column("caloriesBurned", .integer)
                t.column("distanceKm", .double)
                t.column("date", .datetime).notNull()
                t.column("note", .text).notNull().defaults(to: "")
            }
        }

        // Next spheres: migrator.registerMigration("finance-v1") { ... }

        return migrator
    }
}

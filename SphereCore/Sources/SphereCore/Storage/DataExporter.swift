import Foundation
import GRDB

/// Exports every row of the local database into one versioned JSON document —
/// the pre-CloudKit safety hatch so a user is never locked in. Generic over
/// the schema (dumps whatever tables exist), so new spheres export for free.
public enum DataExporter {
    public static let formatVersion = 1

    /// Serializes all user tables to JSON `Data`. Runs on the database's
    /// reader; serialization happens inside the read so the returned value is
    /// a plain `Data` (Sendable-safe).
    public static func exportJSON(from database: AppDatabase, exportedAt: Date = Date()) async throws -> Data {
        try await database.writer.read { db in
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table'
                  AND name NOT LIKE 'sqlite_%'
                  AND name NOT LIKE 'grdb_%'
                ORDER BY name
                """)

            var dump: [String: Any] = [:]
            for table in tables {
                let rows = try Row.fetchAll(db, sql: "SELECT * FROM \"\(table)\"")
                dump[table] = rows.map(jsonRow)
            }

            let root: [String: Any] = [
                "format": "sphere.export",
                "version": formatVersion,
                "exportedAt": ISO8601DateFormatter().string(from: exportedAt),
                "tables": dump,
            ]
            return try JSONSerialization.data(
                withJSONObject: root, options: [.prettyPrinted, .sortedKeys]
            )
        }
    }

    /// Maps a GRDB row to a JSON-object, preserving column types (blobs become
    /// base64 strings, NULLs become JSON null).
    private static func jsonRow(_ row: Row) -> [String: Any] {
        var object: [String: Any] = [:]
        for column in row.columnNames {
            let value: DatabaseValue = row[column]
            if value.isNull {
                object[column] = NSNull()
            } else if let int = Int.fromDatabaseValue(value) {
                object[column] = int
            } else if let double = Double.fromDatabaseValue(value) {
                object[column] = double
            } else if let string = String.fromDatabaseValue(value) {
                object[column] = string
            } else if let data = Data.fromDatabaseValue(value) {
                object[column] = data.base64EncodedString()
            } else {
                object[column] = NSNull()
            }
        }
        return object
    }
}

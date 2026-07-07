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
    ///
    /// When `engram` is provided, the export gains an additive top-level
    /// "engram" section with every stored memory (across all agents) — the
    /// local-first export is incomplete without it, since Engram lives in a
    /// separate database file (`sphere.engram.db`). Passing `nil` keeps the
    /// old behavior for callers that only care about the sphere database.
    public static func exportJSON(
        from database: AppDatabase, engram: EngramStore? = nil, exportedAt: Date = Date()
    ) async throws -> Data {
        let memories = try await engram?.dumpAll() ?? []

        return try await database.writer.read { db in
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

            var root: [String: Any] = [
                "format": "sphere.export",
                "version": formatVersion,
                "exportedAt": ISO8601DateFormatter().string(from: exportedAt),
                "tables": dump,
            ]
            if engram != nil {
                root["engram"] = memories.map(jsonMemory)
            }
            return try JSONSerialization.data(
                withJSONObject: root, options: [.prettyPrinted, .sortedKeys]
            )
        }
    }

    /// Maps an Engram memory to a JSON object with every field the schema
    /// tracks, so the export is a faithful dump (not a lossy summary).
    private static func jsonMemory(_ memory: EngramMemory) -> [String: Any] {
        [
            "id": memory.id,
            "agentId": memory.agentId,
            "content": memory.content,
            "tags": memory.tags,
            "salience": memory.salience,
            "emotionalValence": memory.emotionalValence,
            "importance": memory.importance,
            "accessCount": memory.accessCount,
            "createdAt": ISO8601DateFormatter().string(from: memory.createdAt),
        ]
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

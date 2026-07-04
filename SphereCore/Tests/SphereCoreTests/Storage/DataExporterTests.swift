import Foundation
import Testing
@testable import SphereCore

@Suite("DataExporter")
@MainActor
struct DataExporterTests {
    @Test func exportsRowsAsVersionedJSON() async throws {
        let database = try AppDatabase.inMemory()
        let goals = GoalsStore(database: database)
        try await goals.load()
        try await goals.add(Goal(id: "g1", title: "Ship v1", emoji: "🚀", horizon: .quarter))

        let data = try await DataExporter.exportJSON(from: database)
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(root["format"] as? String == "sphere.export")
        #expect(root["version"] as? Int == DataExporter.formatVersion)

        let tables = try #require(root["tables"] as? [String: Any])
        let goalRows = try #require(tables["goals"] as? [[String: Any]])
        #expect(goalRows.count == 1)
        #expect(goalRows.first?["title"] as? String == "Ship v1")
    }

    @Test func emptyDatabaseExportsEmptyTables() async throws {
        let database = try AppDatabase.inMemory()
        let data = try await DataExporter.exportJSON(from: database)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tables = try #require(root["tables"] as? [String: Any])
        // Tables exist (migrations ran) but hold no rows.
        #expect(!tables.isEmpty)
        let goalRows = try #require(tables["goals"] as? [[String: Any]])
        #expect(goalRows.isEmpty)
    }
}

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

    @Test func exportWithoutEngramOmitsEngramSection() async throws {
        let database = try AppDatabase.inMemory()
        let data = try await DataExporter.exportJSON(from: database)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["engram"] == nil)
    }

    @Test func exportIncludesEngramMemories() async throws {
        let database = try AppDatabase.inMemory()
        let engram = try EngramStore.inMemory()
        try await engram.observe(
            agentId: "health", content: "Ran 5km this morning",
            tags: ["exercise", "cardio"], salience: 0.8, emotionalValence: 0.3
        )
        try await engram.observe(agentId: "finance", content: "Paid rent", salience: 0.6)

        let data = try await DataExporter.exportJSON(from: database, engram: engram)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let memories = try #require(root["engram"] as? [[String: Any]])
        #expect(memories.count == 2)

        let first = try #require(memories.first)
        #expect(first["agentId"] as? String == "health")
        #expect(first["content"] as? String == "Ran 5km this morning")
        #expect(first["tags"] as? [String] == ["exercise", "cardio"])
        #expect(first["salience"] as? Double == 0.8)
        #expect(first["emotionalValence"] as? Double == 0.3)
        #expect(first["accessCount"] as? Int == 0)
        #expect(first["id"] != nil)
        #expect(first["createdAt"] != nil)
        #expect(first["importance"] != nil)

        #expect(memories.last?["content"] as? String == "Paid rent")
    }

    @Test func exportWithEmptyEngramStoreHasEmptyEngramSection() async throws {
        let database = try AppDatabase.inMemory()
        let engram = try EngramStore.inMemory()
        let data = try await DataExporter.exportJSON(from: database, engram: engram)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let memories = try #require(root["engram"] as? [[String: Any]])
        #expect(memories.isEmpty)
    }
}

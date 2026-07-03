import Foundation
import GRDB

/// On-device episodic memory for sphere agents (Engram v1.5).
///
/// One `memories` table + FTS5 index with BM25 ranking, plus an importance
/// score maintained by a periodic decay job (Ebbinghaus curve, see
/// ``DecayConfig``). The schema is column-compatible with the Dart
/// `sphere.engram.db` so existing databases can be imported.
public final class EngramStore: Sendable {
    private let dbWriter: any DatabaseWriter

    public convenience init(path: String) throws {
        try self.init(dbWriter: DatabasePool(path: path))
    }

    /// In-memory store for tests and previews.
    public static func inMemory() throws -> EngramStore {
        try EngramStore(dbWriter: DatabaseQueue())
    }

    private init(dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try Self.migrator.migrate(dbWriter)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE memories (
                  id                TEXT PRIMARY KEY,
                  agent_id          TEXT NOT NULL,
                  content           TEXT NOT NULL,
                  tags              TEXT NOT NULL DEFAULT '',
                  salience          REAL NOT NULL DEFAULT 0.7,
                  emotional_valence REAL NOT NULL DEFAULT 0,
                  importance        REAL NOT NULL DEFAULT 0.7,
                  created_at        INTEGER NOT NULL,
                  accessed_at       INTEGER NOT NULL,
                  access_count      INTEGER NOT NULL DEFAULT 0
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_mem_agent ON memories(agent_id)")
            try db.execute(sql: "CREATE INDEX idx_mem_created ON memories(created_at DESC)")

            try db.execute(sql: """
                CREATE VIRTUAL TABLE memories_fts USING fts5(
                  id UNINDEXED,
                  agent_id UNINDEXED,
                  content,
                  tags,
                  content='memories',
                  content_rowid='rowid'
                )
                """)
            try db.execute(sql: """
                CREATE TRIGGER mem_ai AFTER INSERT ON memories BEGIN
                  INSERT INTO memories_fts(rowid, id, agent_id, content, tags)
                  VALUES (new.rowid, new.id, new.agent_id, new.content, new.tags);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER mem_au AFTER UPDATE OF content, tags ON memories BEGIN
                  INSERT INTO memories_fts(memories_fts, rowid, id, agent_id, content, tags)
                  VALUES ('delete', old.rowid, old.id, old.agent_id, old.content, old.tags);
                  INSERT INTO memories_fts(rowid, id, agent_id, content, tags)
                  VALUES (new.rowid, new.id, new.agent_id, new.content, new.tags);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER mem_ad AFTER DELETE ON memories BEGIN
                  INSERT INTO memories_fts(memories_fts, rowid, id, agent_id, content, tags)
                  VALUES ('delete', old.rowid, old.id, old.agent_id, old.content, old.tags);
                END
                """)
        }
        return migrator
    }

    // MARK: - Write

    /// Stores an observation. Empty content is ignored.
    /// Returns the new memory id, or nil when nothing was stored.
    @discardableResult
    public func observe(
        agentId: String,
        content: String,
        tags: [String] = [],
        salience: Double = 0.7,
        emotionalValence: Double = 0
    ) async throws -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let now = Self.nowMs()
        let id = "\(agentId)_\(now)_\(UUID().uuidString.prefix(8).lowercased())"
        let initialImportance = salience + DecayConfig().beta * emotionalValence
        try await dbWriter.write { db in
            try db.execute(
                sql: """
                    INSERT INTO memories
                      (id, agent_id, content, tags, salience, emotional_valence,
                       importance, created_at, accessed_at, access_count)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                    """,
                arguments: [
                    id, agentId, trimmed, tags.joined(separator: ","),
                    salience, emotionalValence, initialImportance, now, now,
                ]
            )
        }
        return id
    }

    /// Fire-and-forget ``observe(agentId:content:tags:salience:emotionalValence:)``
    /// for synchronous call sites (e.g. store mutations). Errors are swallowed.
    public func note(
        agentId: String,
        content: String,
        tags: [String] = [],
        salience: Double = 0.65
    ) {
        Task {
            try? await self.observe(
                agentId: agentId, content: content, tags: tags, salience: salience
            )
        }
    }

    // MARK: - Recall

    /// BM25 recall scoped to one agent, with recent-k fallback when the query
    /// is empty, unsearchable, or matches nothing. Returned memories are
    /// touched (access_count + accessed_at) to feed the decay job.
    public func recall(_ query: String, agentId: String, k: Int = 8) async throws -> [EngramMemory] {
        try await recall(query, agentId: agentId, k: k, crossAgent: false)
    }

    /// BM25 recall across all agents (Meta Agent path).
    public func crossAgentRecall(_ query: String, k: Int = 12) async throws -> [EngramMemory] {
        try await recall(query, agentId: nil, k: k, crossAgent: true)
    }

    private func recall(
        _ query: String, agentId: String?, k: Int, crossAgent: Bool
    ) async throws -> [EngramMemory] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let ftsQuery = sanitizeFtsQuery(trimmed)
            if !ftsQuery.isEmpty {
                let hits = try await ftsRecall(ftsQuery, agentId: agentId, k: k)
                if !hits.isEmpty { return hits }
            }
        }
        return try await recentMemories(agentId: agentId, k: k)
    }

    private func ftsRecall(_ ftsQuery: String, agentId: String?, k: Int) async throws -> [EngramMemory] {
        try await dbWriter.write { db in
            let agentFilter = agentId != nil ? "AND memories_fts.agent_id = ?" : ""
            var arguments: [any DatabaseValueConvertible] = [ftsQuery]
            if let agentId { arguments.append(agentId) }
            arguments.append(k)

            let rows: [Row]
            do {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT m.id, m.agent_id, m.content, m.tags, m.salience,
                               m.emotional_valence, m.importance, m.access_count,
                               m.created_at, bm25(memories_fts) AS score
                        FROM memories_fts
                        JOIN memories m ON m.id = memories_fts.id
                        WHERE memories_fts MATCH ? \(agentFilter)
                        ORDER BY score, m.importance DESC, m.created_at DESC
                        LIMIT ?
                        """,
                    arguments: StatementArguments(arguments)
                )
            } catch {
                // A sanitized query should never break MATCH; if it somehow
                // does, degrade to the recent fallback instead of failing recall.
                return []
            }
            let memories = rows.map(Self.memory(from:))
            try Self.touch(db, ids: memories.map(\.id))
            return memories
        }
    }

    private func recentMemories(agentId: String?, k: Int) async throws -> [EngramMemory] {
        try await dbWriter.write { db in
            let rows: [Row]
            if let agentId {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, agent_id, content, tags, salience, emotional_valence,
                               importance, access_count, created_at, 0.0 AS score
                        FROM memories WHERE agent_id = ?
                        ORDER BY created_at DESC, rowid DESC LIMIT ?
                        """,
                    arguments: [agentId, k]
                )
            } else {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, agent_id, content, tags, salience, emotional_valence,
                               importance, access_count, created_at, 0.0 AS score
                        FROM memories
                        ORDER BY created_at DESC, rowid DESC LIMIT ?
                        """,
                    arguments: [k]
                )
            }
            let memories = rows.map(Self.memory(from:))
            try Self.touch(db, ids: memories.map(\.id))
            return memories
        }
    }

    // MARK: - Decay

    /// Recomputes the importance score of every memory (see ``DecayConfig``).
    /// Returns the number of memories updated. `now` is injectable for tests.
    @discardableResult
    public func runDecay(config: DecayConfig = DecayConfig(), now: Date = Date()) async throws -> Int {
        try await dbWriter.write { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, salience, emotional_valence, accessed_at, access_count FROM memories"
            )
            guard !rows.isEmpty else { return 0 }

            let statement = try db.makeStatement(sql: "UPDATE memories SET importance = ? WHERE id = ?")
            for row in rows {
                let lastAccess = Date(timeIntervalSince1970: Double(row["accessed_at"] as Int64) / 1000)
                let importance = config.importance(
                    salience: row["salience"],
                    emotionalValence: row["emotional_valence"],
                    lastAccess: lastAccess,
                    accessCount: row["access_count"],
                    now: now
                )
                try statement.execute(arguments: [importance, row["id"] as String])
            }
            return rows.count
        }
    }

    /// Deletes memories whose importance fell below `threshold`.
    /// Run ``runDecay(config:now:)`` first. Returns the number pruned.
    @discardableResult
    public func prune(threshold: Double = DecayConfig().threshold) async throws -> Int {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM memories WHERE importance < ?", arguments: [threshold])
            return db.changesCount
        }
    }

    // MARK: - Stats

    public func count(agentId: String) async throws -> Int {
        try await dbWriter.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM memories WHERE agent_id = ?",
                arguments: [agentId]
            ) ?? 0
        }
    }

    public func countAll() async throws -> Int {
        try await dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memories") ?? 0
        }
    }

    /// Fetches a single memory by id (nil when absent). Does not touch access stats.
    public func memory(id: String) async throws -> EngramMemory? {
        try await dbWriter.read { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT id, agent_id, content, tags, salience, emotional_valence,
                           importance, access_count, created_at, 0.0 AS score
                    FROM memories WHERE id = ?
                    """,
                arguments: [id]
            ).map(Self.memory(from:))
        }
    }

    // MARK: - Helpers

    private static func touch(_ db: Database, ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let placeholders = databaseQuestionMarks(count: ids.count)
        try db.execute(
            sql: "UPDATE memories SET access_count = access_count + 1, accessed_at = ? WHERE id IN (\(placeholders))",
            arguments: StatementArguments([nowMs()] + ids)
        )
    }

    private static func memory(from row: Row) -> EngramMemory {
        let tags = (row["tags"] as String).split(separator: ",").map(String.init)
        let bm25 = row["score"] as Double
        return EngramMemory(
            id: row["id"],
            agentId: row["agent_id"],
            content: row["content"],
            tags: tags,
            salience: row["salience"],
            emotionalValence: row["emotional_valence"],
            importance: row["importance"],
            accessCount: row["access_count"],
            createdAt: Date(timeIntervalSince1970: Double(row["created_at"] as Int64) / 1000),
            score: bm25 < 0 ? min(max(1 + bm25 / 10, 0), 1) : 0.5
        )
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

import Foundation
import GRDB
import Testing
@testable import SphereCore

@Suite("QuickLogSQL")
struct QuickLogSQLTests {
    @Test func incrementWaterAccumulatesAndCaps() async throws {
        let database = try AppDatabase.inMemory()
        let first = try await QuickLogSQL.incrementWater(database.writer, cap: 3)
        #expect(first == 1)
        _ = try await QuickLogSQL.incrementWater(database.writer, cap: 3)
        let third = try await QuickLogSQL.incrementWater(database.writer, cap: 3)
        #expect(third == 3)
        // Capped.
        let capped = try await QuickLogSQL.incrementWater(database.writer, cap: 3)
        #expect(capped == 3)
    }

    @Test func moodAndMeditationWriteThrough() async throws {
        let database = try AppDatabase.inMemory()
        try await QuickLogSQL.setMood(database.writer, score: 9) // clamps to 5
        try await QuickLogSQL.addMeditation(database.writer, minutes: 12)

        let (mood, sessions) = try await database.writer.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT score FROM moods LIMIT 1"),
                try Int.fetchOne(db, sql: "SELECT count(*) FROM meditation_sessions") ?? 0
            )
        }
        #expect(mood == 5)
        #expect(sessions == 1)
    }

    @Test func matchesHealthStoreWaterState() async throws {
        // The store path and the raw path agree (both go through QuickLogSQL).
        let database = try AppDatabase.inMemory()
        let store = await HealthStore(database: database)
        _ = try await store.incrementWater()
        _ = try await store.incrementWater()
        let count = try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT glasses FROM water LIMIT 1")
        }
        #expect(count == 2)
        #expect(await store.waterToday == 2)
    }
}

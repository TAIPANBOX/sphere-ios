import Foundation
import Testing
@testable import SphereCore

@Suite("ReviewStore")
@MainActor
struct ReviewStoreTests {
    private func makeStore() throws -> ReviewStore {
        let database = try AppDatabase.inMemory()
        let health = HealthStore(database: database)
        let finance = FinanceStore(database: database)
        let rest = RestStore(database: database)
        let mindfulness = MindfulnessStore(database: database)
        let hobbies = HobbiesStore(database: database)
        let home = HomeStore(
            health: health,
            learning: LearningStore(database: database),
            career: CareerStore(database: database),
            finance: finance,
            goals: GoalsStore(database: database)
        )
        let insights = InsightsStore(
            health: health, mindfulness: mindfulness, rest: rest,
            finance: finance, hobbies: hobbies
        )
        return ReviewStore(
            database: database, home: home, mindfulness: mindfulness,
            health: health, rest: rest, finance: finance, insights: insights
        )
    }

    @Test func weekAndQuarterKeysAreWellFormed() throws {
        let store = try makeStore()
        let day = ISO8601DateFormatter().date(from: "2026-07-04T12:00:00Z")!
        #expect(store.weekKey(asOf: day).hasPrefix("2026-W"))
        #expect(store.quarterKey(asOf: day) == "2026-Q3")
    }

    @Test func computedScoresCoverEveryScoredSphere() throws {
        let store = try makeStore()
        // HomeStore scores 8 spheres from defaults even with no data.
        #expect(store.computedScores().count == 8)
    }

    @Test func lifeWheelDeltasOnlyForScoredSpheres() throws {
        let store = try makeStore()
        let ratings = Dictionary(uniqueKeysWithValues: SphereType.allCases.map { ($0, 7) })
        let deltas = store.lifeWheelDeltas(selfRatings: ratings)
        // Twelve rated, but only the eight scored spheres produce a delta.
        #expect(deltas.count == 8)
    }

    @Test func emptyWeekYieldsEmptyDigest() throws {
        let store = try makeStore()
        #expect(store.weeklyDigest().isEmpty)
    }

    @Test func saveWeeklyRoundTrips() async throws {
        let store = try makeStore()
        let review = try await store.saveWeekly(content: "A good week.")
        #expect(review.type == .weekly)
        #expect(store.reviews.contains { $0.id == review.id })

        try await store.load()
        #expect(store.reviews.contains { $0.content == "A good week." })
    }

    @Test func saveLifeWheelStoresRatings() async throws {
        let store = try makeStore()
        let review = try await store.saveLifeWheel(
            selfRatings: [.health: 8, .finance: 4], content: "gap noted"
        )
        #expect(review.type == .lifeWheel)
        #expect(review.selfRatings["health"] == 8)
        #expect(review.selfRatings["finance"] == 4)
    }
}

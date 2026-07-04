import Foundation
import Testing
@testable import SphereCore

@Suite("Hobbies extras: milestones, cost/session, taste")
@MainActor
struct HobbiesExtrasTests {
    private func makeStore() throws -> (HobbiesStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (HobbiesStore(database: database), database)
    }

    @Test func costPerSessionDividesSpendBySessions() async throws {
        let (store, _) = try makeStore()
        try await store.load()
        try await store.addHobby(Hobby(id: "h", name: "Climbing", costTotal: 300))
        // No sessions yet → divides by 1.
        #expect(store.costPerSession(for: "h") == 300)
        try await store.logSession(HobbySession(id: "s1", hobbyId: "h", durationMinutes: 60, date: Date()))
        try await store.logSession(HobbySession(id: "s2", hobbyId: "h", durationMinutes: 60, date: Date()))
        #expect(store.costPerSession(for: "h") == 150)
        // A free hobby → nil.
        try await store.addHobby(Hobby(id: "free", name: "Running"))
        #expect(store.costPerSession(for: "free") == nil)
    }

    @Test func averageRatingUsesRatedSessionsOnly() async throws {
        let (store, _) = try makeStore()
        try await store.load()
        try await store.addHobby(Hobby(id: "h", name: "Guitar"))
        try await store.logSession(HobbySession(id: "s1", hobbyId: "h", durationMinutes: 30, date: Date(), rating: 5))
        try await store.logSession(HobbySession(id: "s2", hobbyId: "h", durationMinutes: 30, date: Date(), rating: 3))
        try await store.logSession(HobbySession(id: "s3", hobbyId: "h", durationMinutes: 30, date: Date())) // unrated
        #expect(store.averageRating(for: "h") == 4) // (5+3)/2
    }

    @Test func milestonesToggleAndPersist() async throws {
        let (store, database) = try makeStore()
        try await store.load()
        try await store.addHobby(Hobby(id: "h", name: "Chess"))
        try await store.addMilestone(HobbyMilestone(id: "m", hobbyId: "h", title: "Reach 1500 rating"))
        #expect(store.milestones(for: "h").count == 1)
        try await store.toggleMilestone(id: "m")
        #expect(store.milestones(for: "h").first?.done == true)

        let reloaded = HobbiesStore(database: database)
        try await reloaded.load()
        #expect(reloaded.milestones.first?.done == true)
    }
}

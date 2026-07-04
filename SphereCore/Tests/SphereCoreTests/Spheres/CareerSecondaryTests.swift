import Foundation
import Testing
@testable import SphereCore

@Suite("CareerStore achievements & network")
@MainActor
struct CareerSecondaryTests {
    private func makeStore(engram: EngramStore? = nil) throws -> (CareerStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (CareerStore(database: database, engram: engram), database)
    }

    @Test func achievementsPersistNewestFirstAndNote() async throws {
        let engram = try EngramStore.inMemory()
        let (store, database) = try makeStore(engram: engram)
        let now = Date()
        try await store.addAchievement(Achievement(
            id: "a1", title: "Shipped v1", date: now.addingTimeInterval(-86_400)
        ))
        try await store.addAchievement(Achievement(
            id: "a2", title: "Led migration", date: now, impact: "cut costs 30%"
        ))

        #expect(store.achievements.map(\.id) == ["a2", "a1"])

        let reloaded = CareerStore(database: database)
        try await reloaded.load()
        #expect(reloaded.achievements.map(\.id) == ["a2", "a1"])

        var count = 0
        for _ in 0..<50 where count < 2 {
            count = try await engram.count(agentId: "career")
            if count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        }
        let memories = try await engram.recall("achievement", agentId: "career")
        #expect(memories.contains { $0.content == "Logged achievement: Led migration — cut costs 30%" })

        try await store.removeAchievement(id: "a1")
        #expect(store.achievements.map(\.id) == ["a2"])
    }

    @Test func networkContactAndStaleDetection() async throws {
        let now = Date()
        let (store, database) = try makeStore()
        try await store.addNetworkContact(NetworkContact(
            id: "n1", name: "Olena", role: "PM", company: "Acme",
            lastContact: now.addingTimeInterval(-90 * 86_400)
        ))
        try await store.addNetworkContact(NetworkContact(
            id: "n2", name: "Max", role: "Eng", lastContact: now.addingTimeInterval(-5 * 86_400)
        ))
        try await store.addNetworkContact(NetworkContact(id: "n3", name: "New person"))

        // n1 (90d) and n3 (never) are stale; n1 is more overdue than n3? n3
        // is the 9999 sentinel, so it's first.
        let stale = store.staleContacts(asOf: now)
        #expect(stale.map(\.id) == ["n3", "n1"])

        try await store.markNetworkContacted(id: "n1", on: now)
        #expect(store.network.first { $0.id == "n1" }?.daysSinceContact(asOf: now) == 0)
        #expect(!store.staleContacts(asOf: now).contains { $0.id == "n1" })

        let reloaded = CareerStore(database: database)
        try await reloaded.load()
        #expect(reloaded.network.count == 3)

        try await store.removeNetworkContact(id: "n3")
        #expect(store.network.count == 2)
    }

    @Test func daysSinceContactSentinelForNeverContacted() {
        #expect(NetworkContact(id: "x", name: "Y").daysSinceContact() == 9_999)
    }
}

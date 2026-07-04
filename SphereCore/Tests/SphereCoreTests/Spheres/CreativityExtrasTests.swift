import Foundation
import Testing
@testable import SphereCore

@Suite("Creativity extras: portfolio, work sessions")
@MainActor
struct CreativityExtrasTests {
    private func makeStore() throws -> (CreativityStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (CreativityStore(database: database), database)
    }

    @Test func sessionsAccumulateAndStampProject() async throws {
        let (store, database) = try makeStore()
        try await store.load()
        try await store.add(CreativeProject(id: "p", title: "Novel", createdAt: Date()))
        try await store.logSession(projectId: "p", minutes: 30)
        try await store.logSession(projectId: "p", minutes: 45)

        #expect(store.totalMinutes(for: "p") == 75)
        #expect(store.minutesThisWeek() == 75)
        #expect(store.weeklyMinutes().last == 75) // logged today
        // Project's lastWorkedOn was stamped.
        #expect(store.projects.first?.lastWorkedOn != nil)

        let reloaded = CreativityStore(database: database)
        try await reloaded.load()
        #expect(reloaded.sessions.count == 2)
    }

    @Test func portfolioPersists() async throws {
        let (store, database) = try makeStore()
        try await store.load()
        try await store.addPortfolioItem(PortfolioItem(id: "f", title: "Sunset series", type: .drawing, date: Date()))
        #expect(store.portfolio.count == 1)

        let reloaded = CreativityStore(database: database)
        try await reloaded.load()
        #expect(reloaded.portfolio.first?.title == "Sunset series")
    }
}

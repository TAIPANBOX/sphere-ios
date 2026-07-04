import Foundation
import Testing
@testable import SphereCore

@Suite("QuickCapture end-to-end")
@MainActor
struct QuickCaptureTests {
    private func makeRegistry() throws -> (SphereToolRegistry, HealthStore, MindfulnessStore, FinanceStore) {
        let database = try AppDatabase.inMemory()
        let health = HealthStore(database: database)
        let mindfulness = MindfulnessStore(database: database)
        let finance = FinanceStore(database: database)
        let registry = SphereToolRegistry(tools: health.tools + mindfulness.tools + finance.tools)
        return (registry, health, mindfulness, finance)
    }

    @Test func routesMultipleFactsToTheirStores() async throws {
        let (registry, health, mindfulness, finance) = try makeRegistry()
        try await health.load()
        try await finance.load()

        let results = await QuickCapture.run(
            "water 3, mood 4, spent 4.50 on coffee", registry: registry
        )

        #expect(results.count == 3)
        #expect(results.allSatisfy { !$0.isError })
        #expect(health.waterToday == 3)
        #expect(mindfulness.todaysMood() == 4)
        #expect(finance.transactions.contains { $0.title == "Coffee" && $0.amount == 4.5 })
    }

    @Test func unparseableTextLogsNothing() async throws {
        let (registry, health, _, _) = try makeRegistry()
        try await health.load()
        let results = await QuickCapture.run("remember to call the dentist", registry: registry)
        #expect(results.isEmpty)
        #expect(health.waterToday == 0)
    }
}

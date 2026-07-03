import Foundation
import Testing
@testable import SphereCore

@Suite("TravelStore")
@MainActor
struct TravelStoreTests {
    private func makeStore(engram: EngramStore? = nil) throws -> (TravelStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (TravelStore(database: database, engram: engram), database)
    }

    // MARK: - Trips

    @Test func plansPersistWithChecklists() async throws {
        let (store, database) = try makeStore()
        try await store.add(TravelPlan(
            id: "t1", destination: "Kyoto", country: "Japan", type: .culture,
            packingList: ["Passport": true, "Camera": false],
            documents: ["Visa (if required)": true]
        ))

        let reloaded = TravelStore(database: database)
        try await reloaded.load()
        let plan = try #require(reloaded.plans.first)
        #expect(plan.packingList == ["Passport": true, "Camera": false])
        #expect(plan.documents["Visa (if required)"] == true)
    }

    @Test func addNotesTripIntoEngram() async throws {
        let engram = try EngramStore.inMemory()
        let (store, _) = try makeStore(engram: engram)
        try await store.add(TravelPlan(id: "t1", destination: "Lisbon", country: "Portugal", type: .city))

        var count = 0
        for _ in 0..<50 where count == 0 {
            count = try await engram.count(agentId: "travel")
            if count == 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        let memories = try await engram.recall("trip Lisbon", agentId: "travel")
        #expect(memories.first?.content == "Planning a city trip to Lisbon, Portugal")
    }

    @Test func daysUntilAndNextTrip() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        try await store.add(TravelPlan(
            id: "t1", destination: "Far", status: .booked,
            startDate: now.addingTimeInterval(20 * 86_400)
        ))
        try await store.add(TravelPlan(
            id: "t2", destination: "Soon", status: .booked,
            startDate: now.addingTimeInterval(5 * 86_400)
        ))
        try await store.add(TravelPlan(
            id: "t3", destination: "Sooner but only planned", status: .planned,
            startDate: now.addingTimeInterval(86_400)
        ))
        try await store.add(TravelPlan(
            id: "t4", destination: "Past", status: .booked,
            startDate: now.addingTimeInterval(-86_400)
        ))

        #expect(store.nextTrip(asOf: now)?.destination == "Soon")
        #expect(store.plans.first { $0.id == "t2" }?.daysUntil(asOf: now) == 5)
        #expect(store.plans.first { $0.id == "t4" }?.daysUntil(asOf: now) == nil)
    }

    @Test func packingChecklistLifecycle() async throws {
        let (store, _) = try makeStore()
        try await store.add(TravelPlan(id: "t1", destination: "Alps", type: .mountain))

        try await store.initPackingAndDocs(planId: "t1")
        let seeded = store.plans[0]
        #expect(seeded.packingList["Hiking boots"] == false)
        #expect(seeded.documents.count == TravelPlan.defaultDocuments.count)

        // Seeding is idempotent.
        try await store.togglePackingItem(planId: "t1", item: "Hiking boots")
        try await store.initPackingAndDocs(planId: "t1")
        #expect(store.plans[0].packingList["Hiking boots"] == true)

        try await store.addPackingItem(planId: "t1", item: "Trekking poles")
        try await store.removePackingItem(planId: "t1", item: "Toiletries")
        #expect(store.plans[0].packingList["Trekking poles"] == false)
        #expect(store.plans[0].packingList["Toiletries"] == nil)

        try await store.toggleDocument(planId: "t1", document: "Passport")
        #expect(store.plans[0].documents["Passport"] == true)
    }

    @Test func defaultPackingVariesByType() {
        #expect(TravelPlan.defaultPacking(for: .beach)["Sunscreen"] == false)
        #expect(TravelPlan.defaultPacking(for: .business)["Laptop"] == false)
        #expect(TravelPlan.defaultPacking(for: .city)["Sunscreen"] == nil)
        #expect(TravelPlan.defaultPacking(for: .adventure)["First aid kit"] == false)
    }

    // MARK: - Visited & wishlist

    @Test func visitedDeduplicatesByName() async throws {
        let (store, database) = try makeStore()
        try await store.addVisited(VisitedCountry(name: "Japan", flag: "🇯🇵", year: 2024))
        try await store.addVisited(VisitedCountry(name: "Japan", flag: "🇯🇵", year: 2025))
        #expect(store.visited.count == 1)
        #expect(store.visited[0].year == 2024)

        try await store.removeVisited(name: "Japan")
        let reloaded = TravelStore(database: database)
        try await reloaded.load()
        #expect(reloaded.visited.isEmpty)
    }

    @Test func wishlistRoundTrips() async throws {
        let (store, database) = try makeStore()
        try await store.addWishlist(WishlistDestination(
            id: "w1", destination: "Kyoto", country: "Japan", flag: "🇯🇵"
        ))

        let reloaded = TravelStore(database: database)
        try await reloaded.load()
        #expect(reloaded.wishlist.map(\.destination) == ["Kyoto"])

        try await store.removeWishlist(id: "w1")
        #expect(store.wishlist.isEmpty)
    }

    // MARK: - Agent tools

    @Test func addWishlistToolCreatesAndConfirms() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(
            id: "t1", name: "add_wishlist_destination",
            input: ["destination": "Reykjavík", "country": "Iceland", "flag": "🇮🇸"]
        )
        let result = await registry.execute(call)
        #expect(!result.isError)
        #expect(store.wishlist.first?.destination == "Reykjavík")
        #expect(registry.confirmation(for: call) == "Added to dream list: Reykjavík")

        let bad = await registry.execute(
            LLMToolCall(id: "t2", name: "add_wishlist_destination", input: .object([:]))
        )
        #expect(bad.isError)
    }

    @Test func travelSummaryToolIsSilentAndComplete() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        try await store.add(TravelPlan(
            id: "t1", destination: "Soon", status: .booked,
            startDate: now.addingTimeInterval(3 * 86_400)
        ))
        try await store.addVisited(VisitedCountry(name: "Japan", flag: "🇯🇵"))
        try await store.addWishlist(WishlistDestination(
            id: "w1", destination: "Kyoto", country: "Japan", flag: "🇯🇵"
        ))
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(id: "t1", name: "get_travel_summary", input: .object([:]))
        let result = await registry.execute(call)
        let json = JSONValue.decoded(from: result.content)

        #expect(json?["nextTrip"]?["destination"]?.stringValue == "Soon")
        #expect(json?["nextTrip"]?["daysUntil"]?.intValue == 3)
        #expect(json?["visitedCountries"]?[0]?.stringValue == "Japan")
        #expect(json?["dreamList"]?[0]?["destination"]?.stringValue == "Kyoto")
        #expect(registry.confirmation(for: call) == nil)
    }

    @Test func toolsAreScopedToTravelSphere() throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)
        #expect(
            registry.toolsFor(.travel).map(\.name).sorted()
                == ["add_wishlist_destination", "get_travel_summary"]
        )
        #expect(registry.toolsFor(.rest).isEmpty)
    }
}

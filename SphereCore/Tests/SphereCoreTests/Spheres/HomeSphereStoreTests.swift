import Foundation
import Testing
@testable import SphereCore

@Suite("HomeSphereStore")
@MainActor
struct HomeSphereStoreTests {
    private func makeStore(engram: EngramStore? = nil) throws -> (HomeSphereStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (HomeSphereStore(database: database, engram: engram), database)
    }

    // MARK: - Tasks

    @Test func tasksToggleAndPersist() async throws {
        let engram = try EngramStore.inMemory()
        let (store, database) = try makeStore(engram: engram)
        try await store.add(HomeTask(id: "h1", title: "Fix faucet", category: .repair, createdAt: Date()))

        try await store.toggle(id: "h1")
        #expect(store.openTasks.isEmpty)
        try await store.toggle(id: "h1")
        #expect(store.openTasks.count == 1)

        let reloaded = HomeSphereStore(database: database)
        try await reloaded.load()
        #expect(reloaded.tasks[0].status == .todo)

        var count = 0
        for _ in 0..<50 where count == 0 {
            count = try await engram.count(agentId: "home")
            if count == 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        let memories = try await engram.recall("faucet", agentId: "home")
        #expect(memories.first?.content == "New home task: Fix faucet (repair)")
    }

    @Test func overdueAndDueTodayHelpersForFocusBuilder() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        try await store.add(HomeTask(
            id: "h1", title: "Late", dueDate: now.addingTimeInterval(-2 * 86_400), createdAt: now
        ))
        try await store.add(HomeTask(id: "h2", title: "Today", dueDate: now, createdAt: now))
        try await store.add(HomeTask(
            id: "h3", title: "Tomorrow", dueDate: now.addingTimeInterval(86_400), createdAt: now
        ))
        try await store.add(HomeTask(
            id: "h4", title: "Done late", status: .done,
            dueDate: now.addingTimeInterval(-86_400), createdAt: now
        ))
        try await store.add(HomeTask(id: "h5", title: "No due", createdAt: now))

        #expect(store.overdueTasks(asOf: now).map(\.id) == ["h1"])
        #expect(store.tasksDueToday(asOf: now).map(\.id) == ["h2"])
    }

    // MARK: - Plants

    @Test func plantWateringLogic() async throws {
        let now = Date()
        let (store, database) = try makeStore()
        try await store.addPlant(Plant(id: "p1", name: "Monstera", intervalDays: 3))
        try await store.addPlant(Plant(
            id: "p2", name: "Fern",
            lastWatered: now.addingTimeInterval(-4 * 86_400), intervalDays: 3
        ))
        try await store.addPlant(Plant(
            id: "p3", name: "Cactus",
            lastWatered: now.addingTimeInterval(-86_400), intervalDays: 14
        ))

        // Never watered + overdue fern are thirsty; cactus is fine.
        #expect(store.needsWateringCount(asOf: now) == 2)
        #expect(store.plants.first { $0.id == "p3" }?.daysUntilWatering(asOf: now) == 13)

        try await store.water(id: "p2", on: now)
        #expect(store.needsWateringCount(asOf: now) == 1)

        let reloaded = HomeSphereStore(database: database)
        try await reloaded.load()
        #expect(reloaded.plants.first { $0.id == "p2" }?.needsWatering(asOf: now) == false)
    }

    // MARK: - Shopping

    @Test func shoppingListLifecycle() async throws {
        let (store, database) = try makeStore()
        try await store.addShoppingItem(ShoppingItem(id: "s1", name: "Milk"))
        try await store.addShoppingItem(ShoppingItem(id: "s2", name: "Bread"))
        try await store.addShoppingItem(ShoppingItem(id: "s3", name: "Eggs"))

        try await store.toggleShoppingItem(id: "s1")
        try await store.toggleShoppingItem(id: "s2")
        #expect(store.uncheckedCount == 1)

        try await store.clearChecked()
        #expect(store.shopping.map(\.name) == ["Eggs"])

        let reloaded = HomeSphereStore(database: database)
        try await reloaded.load()
        #expect(reloaded.shopping.map(\.name) == ["Eggs"])
    }

    // MARK: - Agent tools

    @Test func addHomeTaskToolCreatesAndConfirms() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(
            id: "t1", name: "add_home_task",
            input: ["title": "Change air filter", "category": "repair", "dueDate": "2026-07-15"]
        )
        let result = await registry.execute(call)
        #expect(!result.isError)
        #expect(store.tasks[0].category == .repair)
        #expect(store.tasks[0].dueDate.map { DayKey.make($0) } == "2026-07-15")
        #expect(registry.confirmation(for: call) == "Added home task: Change air filter")
    }

    @Test func addShoppingItemToolCreatesAndConfirms() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(
            id: "t1", name: "add_shopping_item", input: ["name": "Молоко", "category": "Groceries"]
        )
        let result = await registry.execute(call)
        #expect(!result.isError)
        #expect(store.shopping[0].name == "Молоко")
        #expect(registry.confirmation(for: call) == "Added to shopping list: Молоко")

        let bad = await registry.execute(
            LLMToolCall(id: "t2", name: "add_shopping_item", input: .object([:]))
        )
        #expect(bad.isError)
    }

    @Test func homeSummaryToolIsSilentAndComplete() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        try await store.add(HomeTask(
            id: "h1", title: "Water bill", category: .bills,
            dueDate: now.addingTimeInterval(-86_400), createdAt: now
        ))
        try await store.addPlant(Plant(id: "p1", name: "Monstera"))
        try await store.addShoppingItem(ShoppingItem(id: "s1", name: "Milk"))
        try await store.addShoppingItem(ShoppingItem(id: "s2", name: "Done", checked: true))
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(id: "t1", name: "get_home_summary", input: .object([:]))
        let result = await registry.execute(call)
        let json = JSONValue.decoded(from: result.content)

        #expect(json?["openTasks"]?[0]?["title"]?.stringValue == "Water bill")
        #expect(json?["openTasks"]?[0]?["overdue"]?.boolValue == true)
        #expect(json?["plantsNeedingWater"]?[0]?.stringValue == "Monstera")
        #expect(json?["shoppingList"]?.arrayValue?.map(\.stringValue) == ["Milk"])
        #expect(registry.confirmation(for: call) == nil)
    }

    @Test func toolsAreScopedToHomeSphere() throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)
        #expect(
            registry.toolsFor(.home).map(\.name).sorted()
                == ["add_home_task", "add_shopping_item", "get_home_summary"]
        )
        #expect(registry.toolsFor(.mindfulness).isEmpty)
    }
}

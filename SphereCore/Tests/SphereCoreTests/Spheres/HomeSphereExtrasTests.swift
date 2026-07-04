import Foundation
import Testing
@testable import SphereCore

@Suite("RecurringChore respawn")
struct RecurringChoreTests {
    private let cal = DayKey.calendar
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func recurringSpawnsNextOccurrence() {
        let task = HomeTask(
            id: "t", title: "Vacuum", dueDate: date(2026, 7, 4),
            isRecurring: true, recurrenceDays: 7, createdAt: date(2026, 7, 1)
        )
        let next = try! #require(RecurringChore.nextOccurrence(after: task, completedAt: date(2026, 7, 4)))
        #expect(next.title == "Vacuum")
        #expect(next.status == .todo)
        #expect(cal.startOfDay(for: next.dueDate!) == date(2026, 7, 11))
    }

    @Test func nonRecurringSpawnsNothing() {
        let task = HomeTask(id: "t", title: "Fix shelf", createdAt: date(2026, 7, 1))
        #expect(RecurringChore.nextOccurrence(after: task) == nil)
    }

    @Test func warrantyDaysLeftCounts() {
        let appliance = Appliance(id: "a", name: "Fridge", warrantyUntil: date(2026, 7, 20))
        #expect(appliance.warrantyDaysLeft(asOf: date(2026, 7, 4)) == 16)
    }
}

@Suite("Home sphere extras: chores, appliances, inventory, utilities")
@MainActor
struct HomeSphereExtrasTests {
    private func makeStore() throws -> (HomeSphereStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (HomeSphereStore(database: database), database)
    }

    @Test func completingRecurringChoreRespawnsIt() async throws {
        let (store, _) = try makeStore()
        try await store.load()
        try await store.add(HomeTask(
            id: "t", title: "Water plants", dueDate: Date(),
            isRecurring: true, recurrenceDays: 3, createdAt: Date()
        ))
        #expect(store.openTasks.count == 1)

        try await store.toggle(id: "t") // complete it
        // Original done + a fresh open occurrence.
        #expect(store.tasks.count == 2)
        #expect(store.openTasks.count == 1)
        #expect(store.openTasks.first?.title == "Water plants")
    }

    @Test func applianceWarrantyRadarAndInventoryLending() async throws {
        let (store, database) = try makeStore()
        try await store.load()
        let soon = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        let farOff = Calendar.current.date(byAdding: .day, value: 400, to: Date())!
        try await store.addAppliance(Appliance(id: "a1", name: "Washer", warrantyUntil: soon))
        try await store.addAppliance(Appliance(id: "a2", name: "TV", warrantyUntil: farOff))
        #expect(store.warrantyExpiringSoon(within: 30).map(\.id) == ["a1"])

        try await store.addInventoryItem(InventoryItem(id: "i1", name: "Drill", lentTo: "Ostap"))
        try await store.addInventoryItem(InventoryItem(id: "i2", name: "Ladder"))
        #expect(store.lentItems.map(\.name) == ["Drill"])

        let reloaded = HomeSphereStore(database: database)
        try await reloaded.load()
        #expect(reloaded.appliances.count == 2)
        #expect(reloaded.inventory.count == 2)
    }

    @Test func utilitiesAndRenovationsPersist() async throws {
        let (store, database) = try makeStore()
        try await store.load()
        try await store.addUtilityReading(UtilityReading(id: "u", kind: .electricity, value: 1240, cost: 55, date: Date()))
        try await store.addRenovation(RenovationProject(id: "r", name: "Kitchen", status: .inProgress, budget: 5000, spent: 1200))

        let reloaded = HomeSphereStore(database: database)
        try await reloaded.load()
        #expect(reloaded.utilityReadings.first?.kind == .electricity)
        #expect(reloaded.renovations.first?.status == .inProgress)
    }
}

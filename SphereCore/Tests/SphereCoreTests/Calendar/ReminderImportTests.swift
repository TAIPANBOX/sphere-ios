import Foundation
import Testing
@testable import SphereCore

@Suite("ReminderImport")
struct ReminderImportTests {
    private func reminder(_ id: String, _ title: String, due: Date? = nil) -> ImportedReminder {
        ImportedReminder(id: id, title: title, dueDate: due)
    }

    @Test func filtersOutExistingByTitleCaseInsensitive() {
        let fresh = ReminderImport.newTasks(
            from: [reminder("1", "buy milk"), reminder("2", "Renew passport")],
            existingTitles: ["Buy Milk"]
        )
        #expect(fresh.map(\.title) == ["Renew passport"])
    }

    @Test func dedupesWithinImportBatch() {
        let fresh = ReminderImport.newTasks(
            from: [reminder("1", "Call plumber"), reminder("2", "  call plumber ")],
            existingTitles: []
        )
        #expect(fresh.count == 1)
    }

    @Test func skipsBlankTitles() {
        let fresh = ReminderImport.newTasks(from: [reminder("1", "   ")], existingTitles: [])
        #expect(fresh.isEmpty)
    }

    @Test func makeTaskCarriesTitleAndDueDate() {
        let due = Date(timeIntervalSince1970: 0)
        let task = ReminderImport.makeTask(from: ImportedReminder(id: "1", title: "Ship it", dueDate: due))
        #expect(task.title == "Ship it")
        #expect(task.dueDate == due)
    }

    @Test func makeTaskWithoutDueDateLeavesItNil() {
        let task = ReminderImport.makeTask(from: ImportedReminder(id: "1", title: "Someday"))
        #expect(task.dueDate == nil)
    }
}

/// Serves fixed reminders and records whether access was requested.
private actor FakeRemindersProvider: RemindersProviding {
    let reminders: [ImportedReminder]
    let grant: Bool
    var accessRequested = false

    init(reminders: [ImportedReminder], grant: Bool = true) {
        self.reminders = reminders
        self.grant = grant
    }

    func requestRemindersAccess() async -> Bool { accessRequested = true; return grant }
    func fetchIncompleteReminders() async -> [ImportedReminder] { reminders }
}

@Suite("CareerStore reminders import")
@MainActor
struct CareerRemindersImportTests {
    private func makeStore(_ provider: FakeRemindersProvider?) throws -> CareerStore {
        let database = try AppDatabase.inMemory()
        return CareerStore(database: database, remindersProvider: provider)
    }

    @Test func importAddsNewRemindersAsTasks() async throws {
        let provider = FakeRemindersProvider(reminders: [
            ImportedReminder(id: "1", title: "Pack for trip"),
            ImportedReminder(id: "2", title: "Renew license"),
        ])
        let store = try makeStore(provider)
        let count = await store.importRemindersFromDevice()
        #expect(count == 2)
        #expect(store.tasks.count == 2)
        #expect(await provider.accessRequested)
    }

    @Test func importSkipsReminderMatchingOpenTask() async throws {
        let provider = FakeRemindersProvider(reminders: [
            ImportedReminder(id: "1", title: "pack for trip"),
        ])
        let store = try makeStore(provider)
        try await store.add(CareerTask(id: "t1", title: "Pack for trip", createdAt: Date()))

        let count = await store.importRemindersFromDevice()
        #expect(count == 0)
        #expect(store.tasks.count == 1)
    }

    @Test func importDoesNotSkipWhenMatchingTaskIsDone() async throws {
        let provider = FakeRemindersProvider(reminders: [
            ImportedReminder(id: "1", title: "Pack for trip"),
        ])
        let store = try makeStore(provider)
        try await store.add(CareerTask(id: "t1", title: "Pack for trip", status: .done, createdAt: Date()))

        // Done tasks aren't in openTasks, so the reminder is imported again as
        // a fresh open task — matches ReminderImport's "existingTitles" being
        // sourced from open tasks only.
        let count = await store.importRemindersFromDevice()
        #expect(count == 1)
        #expect(store.tasks.count == 2)
    }

    @Test func deniedAccessYieldsNothing() async throws {
        let provider = FakeRemindersProvider(
            reminders: [ImportedReminder(id: "1", title: "Task")], grant: false
        )
        let store = try makeStore(provider)
        #expect(await store.importRemindersFromDevice() == 0)
        #expect(store.tasks.isEmpty)
    }

    @Test func noProvider() async throws {
        let store = try makeStore(nil)
        #expect(store.hasRemindersProvider == false)
        #expect(await store.importRemindersFromDevice() == 0)
    }

    @Test func importedTaskCarriesDueDate() async throws {
        let due = Date().addingTimeInterval(86_400)
        let provider = FakeRemindersProvider(reminders: [
            ImportedReminder(id: "1", title: "Submit report", dueDate: due),
        ])
        let store = try makeStore(provider)
        _ = await store.importRemindersFromDevice()
        #expect(store.tasks.first?.dueDate == due)
    }
}

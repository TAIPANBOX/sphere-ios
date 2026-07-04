import Foundation
import Testing
@testable import SphereCore

@Suite("MeetingPrep + custom dates")
struct MeetingPrepTests {
    private let cal = Calendar.current
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func prepAssemblesGlanceableFacts() {
        let now = date(2026, 7, 4)
        var contact = Contact(id: "c", name: "Ostap", birthday: date(1990, 7, 20))
        contact.lastContact = date(2026, 6, 4) // 30 days ago
        contact.importantInfo = "Started a new job"
        contact.giftIdeas = ["Book", "Coffee"]
        let facts = MeetingPrep.facts(for: contact, asOf: now)
        #expect(facts.contains { $0.contains("30 days ago") })
        #expect(facts.contains { $0.contains("Birthday in 16") })
        #expect(facts.contains("Started a new job"))
        #expect(facts.contains { $0.contains("Gift ideas: Book, Coffee") })
    }

    @Test func customDateRecurringRollsToNextYear() {
        let now = date(2026, 7, 4)
        let anniversary = CustomDate(id: "d", contactId: "c", label: "Anniversary", date: date(2020, 7, 10))
        #expect(anniversary.daysUntil(asOf: now) == 6)
        // A past one-off returns nil.
        let oneOff = CustomDate(id: "o", contactId: "c", label: "Concert", date: date(2026, 6, 1), recursYearly: false)
        #expect(oneOff.daysUntil(asOf: now) == nil)
    }
}

@Suite("Relationships extras: custom dates, templates, prep")
@MainActor
struct RelationshipsExtrasTests {
    private func makeStore() throws -> (RelationshipsStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (RelationshipsStore(database: database), database)
    }

    @Test func customDatesAndTemplatesPersist() async throws {
        let (store, database) = try makeStore()
        try await store.load()
        try await store.add(Contact(id: "c", name: "Iryna"))
        try await store.addCustomDate(CustomDate(id: "d", contactId: "c", label: "Anniversary", date: Date()))
        #expect(store.customDates(for: "c").count == 1)

        // No user templates → seeds surface.
        #expect(store.effectiveTemplates.count == MessageTemplate.seeds.count)
        try await store.addTemplate(MessageTemplate(id: "t", title: "Hi", body: "Hello!"))
        #expect(store.effectiveTemplates.count == 1)

        let reloaded = RelationshipsStore(database: database)
        try await reloaded.load()
        #expect(reloaded.customDates.count == 1)
        #expect(reloaded.templates.count == 1)
    }

    @Test func upcomingDatesIncludesBirthdaysAndCustom() async throws {
        let (store, _) = try makeStore()
        try await store.load()
        let cal = Calendar.current
        let now = Date()
        let soon = cal.date(byAdding: .day, value: 5, to: now)!
        var contact = Contact(id: "c", name: "Anna")
        contact.birthday = soon
        try await store.add(contact)
        try await store.addCustomDate(CustomDate(
            id: "d", contactId: "c", label: "Work-versary",
            date: cal.date(byAdding: .day, value: 10, to: now)!
        ))
        let upcoming = store.upcomingDates(within: 30, asOf: now)
        #expect(upcoming.count == 2)
        // Sorted soonest first → birthday (5d) before work-versary (10d).
        #expect(upcoming.first?.label == "Birthday")
    }
}

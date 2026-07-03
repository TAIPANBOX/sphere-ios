import Foundation
import Testing
@testable import SphereCore

@Suite("RelationshipsStore")
@MainActor
struct RelationshipsStoreTests {
    private func makeStore(engram: EngramStore? = nil) throws -> (RelationshipsStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (RelationshipsStore(database: database, engram: engram), database)
    }

    private func birthday(inDays days: Int, from now: Date, yearsAgo: Int = 30) -> Date {
        let calendar = Calendar.current
        let target = calendar.startOfDay(for: now).addingTimeInterval(Double(days) * 86_400)
        return calendar.date(byAdding: .year, value: -yearsAgo, to: target)!
    }

    // MARK: - Birthdays

    @Test func daysUntilBirthdayRollsOverYear() throws {
        let now = Date()
        let inFive = Contact(id: "c1", name: "A", birthday: birthday(inDays: 5, from: now))
        #expect(inFive.daysUntilBirthday(asOf: now) == 5)

        let today = Contact(id: "c2", name: "B", birthday: birthday(inDays: 0, from: now))
        #expect(today.daysUntilBirthday(asOf: now) == 0)

        // Passed yesterday → next year (364 or 365 days depending on leap).
        let passed = Contact(id: "c3", name: "C", birthday: birthday(inDays: -1, from: now))
        let days = try #require(passed.daysUntilBirthday(asOf: now))
        #expect(days >= 363 && days <= 366)

        #expect(Contact(id: "c4", name: "D").daysUntilBirthday(asOf: now) == nil)
    }

    @Test func upcomingBirthdaysFilterAndSort() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        try await store.add(Contact(id: "c1", name: "Soon", birthday: birthday(inDays: 3, from: now)))
        try await store.add(Contact(id: "c2", name: "Sooner", birthday: birthday(inDays: 1, from: now)))
        try await store.add(Contact(id: "c3", name: "Far", birthday: birthday(inDays: 60, from: now)))
        try await store.add(Contact(id: "c4", name: "None"))

        #expect(store.upcomingBirthdays(asOf: now).map(\.name) == ["Sooner", "Soon"])
    }

    // MARK: - Check-ins

    @Test func needsCheckinLogic() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        try await store.add(Contact(id: "c1", name: "Never contacted"))
        try await store.add(Contact(
            id: "c2", name: "Recent",
            lastContact: now.addingTimeInterval(-5 * 86_400), reminderDays: 30
        ))
        try await store.add(Contact(
            id: "c3", name: "Overdue",
            lastContact: now.addingTimeInterval(-40 * 86_400), reminderDays: 30
        ))

        #expect(Set(store.needsCheckin(asOf: now).map(\.name)) == ["Never contacted", "Overdue"])

        try await store.markContacted(id: "c3", on: now)
        #expect(!store.contacts.first { $0.id == "c3" }!.needsCheckin(asOf: now))
    }

    @Test func contactPersistsWithPersonalContext() async throws {
        let engram = try EngramStore.inMemory()
        let (store, database) = try makeStore(engram: engram)
        try await store.add(Contact(id: "c1", name: "Olena", type: .family, note: "Sister"))
        try await store.addGiftIdea(id: "c1", idea: "Vinyl record")
        try await store.addMeetingNote(id: "c1", note: "Talked about her new job")

        let reloaded = RelationshipsStore(database: database)
        try await reloaded.load()
        let contact = try #require(reloaded.contacts.first)
        #expect(contact.giftIdeas == ["Vinyl record"])
        #expect(contact.meetingNotes == ["Talked about her new job"])

        var count = 0
        for _ in 0..<50 where count == 0 {
            count = try await engram.count(agentId: "relationships")
            if count == 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        let memories = try await engram.recall("Olena", agentId: "relationships")
        #expect(memories.first?.content == "Added contact: Olena (family)")
    }

    // MARK: - Agent tools

    @Test func addContactToolCreatesWithBirthday() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(
            id: "t1", name: "add_contact",
            input: ["name": "Марта", "type": "friend", "birthday": "1994-03-08"]
        )
        let result = await registry.execute(call)
        #expect(!result.isError)
        let contact = try #require(store.contacts.first)
        #expect(contact.name == "Марта")
        #expect(contact.birthday != nil)
        #expect(registry.confirmation(for: call) == "Added contact: Марта")
    }

    @Test func markContactedToolMatchesByNameAndListsOnMiss() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        try await store.add(Contact(
            id: "c1", name: "Olena",
            lastContact: now.addingTimeInterval(-90 * 86_400)
        ))
        let registry = SphereToolRegistry(tools: store.tools)

        let good = await registry.execute(
            LLMToolCall(id: "t1", name: "mark_contacted", input: ["name": "olena"])
        )
        #expect(!good.isError)
        #expect(!store.contacts[0].needsCheckin(asOf: now))

        let miss = await registry.execute(
            LLMToolCall(id: "t2", name: "mark_contacted", input: ["name": "Bohdan"])
        )
        #expect(miss.isError)
        #expect(miss.content.contains("Olena"))
    }

    @Test func relationshipsSummaryToolIsSilentAndComplete() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        try await store.add(Contact(
            id: "c1", name: "Olena", type: .family,
            birthday: birthday(inDays: 2, from: now), note: "Sister"
        ))
        try await store.add(Contact(id: "c2", name: "Max"))
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(id: "t1", name: "get_relationships_summary", input: .object([:]))
        let result = await registry.execute(call)
        let json = JSONValue.decoded(from: result.content)

        #expect(json?["contacts"]?.arrayValue?.count == 2)
        #expect(json?["upcomingBirthdays"]?[0]?["name"]?.stringValue == "Olena")
        #expect(json?["upcomingBirthdays"]?[0]?["daysUntil"]?.intValue == 2)
        #expect(json?["needsCheckin"]?.arrayValue?.map(\.stringValue).contains("Max") == true)
        #expect(registry.confirmation(for: call) == nil)
    }

    @Test func toolsAreScopedToRelationshipsSphere() throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)
        #expect(
            registry.toolsFor(.relationships).map(\.name).sorted()
                == ["add_contact", "get_relationships_summary", "mark_contacted"]
        )
        #expect(registry.toolsFor(.hobbies).isEmpty)
    }
}

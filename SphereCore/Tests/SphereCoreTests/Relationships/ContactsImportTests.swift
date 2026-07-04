import Foundation
import Testing
@testable import SphereCore

@Suite("ContactImport")
struct ContactImportTests {
    private func imported(_ id: String, _ name: String) -> ImportedContact {
        ImportedContact(id: id, name: name)
    }

    @Test func filtersOutExistingByNameCaseInsensitive() {
        let existing = [Contact(id: "c1", name: "Maria Silva")]
        let fresh = ContactImport.newContacts(
            from: [imported("1", "maria silva"), imported("2", "Ivan Petrov")],
            existing: existing
        )
        #expect(fresh.map(\.name) == ["Ivan Petrov"])
    }

    @Test func dedupesWithinImportBatch() {
        let fresh = ContactImport.newContacts(
            from: [imported("1", "Anna"), imported("2", "  anna ")],
            existing: []
        )
        #expect(fresh.count == 1)
    }

    @Test func skipsBlankNames() {
        let fresh = ContactImport.newContacts(from: [imported("1", "   ")], existing: [])
        #expect(fresh.isEmpty)
    }

    @Test func makeContactCarriesNameAndBirthday() {
        let bday = Date(timeIntervalSince1970: 0)
        let contact = ContactImport.makeContact(
            from: ImportedContact(id: "1", name: "Lena", birthday: bday)
        )
        #expect(contact.name == "Lena")
        #expect(contact.birthday == bday)
        #expect(contact.note == "Imported from Contacts")
    }
}

/// Serves fixed contacts and records whether access was requested.
private actor FakeContactsProvider: ContactsProviding {
    let contacts: [ImportedContact]
    let grant: Bool
    var accessRequested = false

    init(contacts: [ImportedContact], grant: Bool = true) {
        self.contacts = contacts
        self.grant = grant
    }

    func requestAccess() async -> Bool { accessRequested = true; return grant }
    func fetchContacts() async -> [ImportedContact] { contacts }
}

@Suite("RelationshipsStore contacts import")
@MainActor
struct ContactsImportStoreTests {
    private func makeStore(_ provider: FakeContactsProvider?) throws -> RelationshipsStore {
        let database = try AppDatabase.inMemory()
        return RelationshipsStore(database: database, contactsProvider: provider)
    }

    @Test func importableExcludesExisting() async throws {
        let provider = FakeContactsProvider(contacts: [
            ImportedContact(id: "1", name: "Maria"),
            ImportedContact(id: "2", name: "Ivan"),
        ])
        let store = try makeStore(provider)
        try await store.add(Contact(id: "c1", name: "Maria"))
        let importable = await store.importableContacts()
        #expect(importable.map(\.name) == ["Ivan"])
        #expect(await provider.accessRequested)
    }

    @Test func importAddsSelectedContacts() async throws {
        let store = try makeStore(FakeContactsProvider(contacts: []))
        let count = await store.importContacts([
            ImportedContact(id: "1", name: "Ivan"),
            ImportedContact(id: "2", name: "Lena"),
        ])
        #expect(count == 2)
        #expect(store.contacts.count == 2)
    }

    @Test func deniedAccessYieldsNothing() async throws {
        let provider = FakeContactsProvider(contacts: [ImportedContact(id: "1", name: "Ivan")], grant: false)
        let store = try makeStore(provider)
        #expect(await store.importableContacts().isEmpty)
    }

    @Test func noProvider() async throws {
        let store = try makeStore(nil)
        #expect(store.hasContactsProvider == false)
        #expect(await store.importableContacts().isEmpty)
    }
}

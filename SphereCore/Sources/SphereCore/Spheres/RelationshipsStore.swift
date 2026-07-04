import Foundation
import GRDB
import Observation

/// Relationships sphere store: contacts with birthdays, check-in reminders,
/// and per-person context. Follows the golden-template shape
/// (docs/HANDOFF.md).
///
/// Birthday push reminders are an app-target concern: the composition root
/// observes `contacts` and (re)schedules UserNotifications there.
@MainActor
@Observable
public final class RelationshipsStore {
    public private(set) var contacts: [Contact] = []
    public private(set) var customDates: [CustomDate] = []
    public private(set) var templates: [MessageTemplate] = []

    private let database: AppDatabase
    private let engram: EngramStore?
    private let contactsProvider: (any ContactsProviding)?

    public init(
        database: AppDatabase, engram: EngramStore? = nil,
        contactsProvider: (any ContactsProviding)? = nil
    ) {
        self.database = database
        self.engram = engram
        self.contactsProvider = contactsProvider
    }

    public func load() async throws {
        let (contacts, customDates, templates) = try await database.writer.read { db in
            (
                try Contact.fetchAll(db),
                try CustomDate.fetchAll(db),
                try MessageTemplate.fetchAll(db)
            )
        }
        self.contacts = contacts
        self.customDates = customDates
        self.templates = templates
    }

    // MARK: - Custom dates

    public func customDates(for contactId: String) -> [CustomDate] {
        customDates.filter { $0.contactId == contactId }
    }

    public func addCustomDate(_ date: CustomDate) async throws {
        try await database.writer.write { db in try date.insert(db) }
        customDates.append(date)
    }

    public func removeCustomDate(id: String) async throws {
        _ = try await database.writer.write { db in try CustomDate.deleteOne(db, key: id) }
        customDates.removeAll { $0.id == id }
    }

    /// Contacts with a birthday or custom date within `days`, soonest first —
    /// beyond just birthdays.
    public func upcomingDates(within days: Int = 30, asOf now: Date = Date())
        -> [(contact: Contact, label: String, days: Int)] {
        var result: [(Contact, String, Int)] = []
        for contact in contacts {
            if let d = contact.daysUntilBirthday(asOf: now), d <= days {
                result.append((contact, "Birthday", d))
            }
            for custom in customDates where custom.contactId == contact.id {
                if let d = custom.daysUntil(asOf: now), d <= days {
                    result.append((contact, custom.label, d))
                }
            }
        }
        return result.sorted { $0.2 < $1.2 }.map { (contact: $0.0, label: $0.1, days: $0.2) }
    }

    // MARK: - Message templates

    public func addTemplate(_ template: MessageTemplate) async throws {
        try await database.writer.write { db in try template.insert(db) }
        templates.append(template)
    }

    public func removeTemplate(id: String) async throws {
        _ = try await database.writer.write { db in try MessageTemplate.deleteOne(db, key: id) }
        templates.removeAll { $0.id == id }
    }

    /// The user's templates, or the built-in seeds when they have none.
    public var effectiveTemplates: [MessageTemplate] {
        templates.isEmpty ? MessageTemplate.seeds : templates
    }

    // MARK: - Pre-meeting prep (gem)

    /// Glanceable facts to review before seeing someone.
    public func prepFacts(for contactId: String, asOf now: Date = Date()) -> [String] {
        guard let contact = contacts.first(where: { $0.id == contactId }) else { return [] }
        return MeetingPrep.facts(for: contact, customDates: customDates, asOf: now)
    }

    // MARK: - Contacts

    public func add(_ contact: Contact) async throws {
        try await database.writer.write { db in try contact.insert(db) }
        contacts.append(contact)
        engram?.note(
            agentId: SphereType.relationships.rawValue,
            content: "Added contact: \(contact.name) (\(contact.type.rawValue))",
            tags: ["log", "relationships", "contact"]
        )
    }

    public func update(_ contact: Contact) async throws {
        try await database.writer.write { db in try contact.save(db) }
        contacts = contacts.map { $0.id == contact.id ? contact : $0 }
    }

    // MARK: - Contacts import

    public var hasContactsProvider: Bool { contactsProvider != nil }

    /// Device contacts not yet in the sphere, ready for the user to pick from.
    /// Empty if access is denied or the provider is absent.
    public func importableContacts() async -> [ImportedContact] {
        guard let contactsProvider else { return [] }
        guard await contactsProvider.requestAccess() else { return [] }
        let fetched = await contactsProvider.fetchContacts()
        return ContactImport.newContacts(from: fetched, existing: contacts)
    }

    /// Adds the chosen imported contacts, skipping any that now duplicate an
    /// existing name. Returns how many were added.
    @discardableResult
    public func importContacts(_ selected: [ImportedContact], now: Date = Date()) async -> Int {
        let fresh = ContactImport.newContacts(from: selected, existing: contacts)
        var added = 0
        for imported in fresh {
            let contact = ContactImport.makeContact(from: imported, now: now)
            try? await add(contact)
            added += 1
        }
        return added
    }

    public func remove(id: String) async throws {
        _ = try await database.writer.write { db in try Contact.deleteOne(db, key: id) }
        contacts.removeAll { $0.id == id }
    }

    public func markContacted(id: String, on date: Date = Date()) async throws {
        guard var contact = contacts.first(where: { $0.id == id }) else { return }
        contact.lastContact = date
        try await update(contact)
        engram?.note(
            agentId: SphereType.relationships.rawValue,
            content: "Caught up with \(contact.name)",
            tags: ["log", "relationships", "checkin"]
        )
    }

    public func addGiftIdea(id: String, idea: String) async throws {
        guard var contact = contacts.first(where: { $0.id == id }) else { return }
        contact.giftIdeas.append(idea)
        try await update(contact)
    }

    public func addMeetingNote(id: String, note: String) async throws {
        guard var contact = contacts.first(where: { $0.id == id }) else { return }
        contact.meetingNotes.append(note)
        try await update(contact)
    }

    // MARK: - Derived

    /// Contacts with a birthday within 30 days, soonest first (feeds
    /// Today's Focus).
    public func upcomingBirthdays(asOf now: Date = Date()) -> [Contact] {
        contacts
            .filter { ($0.daysUntilBirthday(asOf: now) ?? 999) <= 30 }
            .sorted { ($0.daysUntilBirthday(asOf: now) ?? 999) < ($1.daysUntilBirthday(asOf: now) ?? 999) }
    }

    public func needsCheckin(asOf now: Date = Date()) -> [Contact] {
        contacts.filter { $0.needsCheckin(asOf: now) }
    }

    // MARK: - Agent tools

    /// NEW relative to the Dart version (which had no relationships tools),
    /// following the wave-2 write + silent-lookup convention.
    public nonisolated var tools: [SphereTool] {
        [
            SphereTool(
                definition: LLMTool(
                    name: "add_contact",
                    description: "Add a person to the user's relationships. type is one of "
                        + "family, friend, colleague, romantic, mentor, other. Use when the "
                        + "user mentions someone new they want to keep in touch with.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string", "minLength": 1],
                            "type": [
                                "type": "string",
                                "enum": ["family", "friend", "colleague", "romantic", "mentor", "other"],
                            ],
                            "birthday": [
                                "type": "string",
                                "description": "Optional ISO-8601 date (YYYY-MM-DD)",
                            ],
                            "note": ["type": "string"],
                        ],
                        "required": ["name"],
                    ]
                ),
                spheres: [.relationships],
                confirmation: { input in
                    "Added contact: \(input["name"]?.stringValue ?? "")"
                },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let name = input["name"]?.stringValue, !name.isEmpty else {
                        throw AgentToolInputError("name is required")
                    }
                    let contact = Contact(
                        id: Contact.newID(),
                        name: name,
                        type: input["type"]?.stringValue
                            .flatMap(RelationshipType.init(rawValue:)) ?? .friend,
                        birthday: input["birthday"]?.stringValue.flatMap(CareerStore.parseDueDate),
                        note: input["note"]?.stringValue ?? ""
                    )
                    try await self.add(contact)
                    return JSONValue.object(["ok": true, "id": .string(contact.id)]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "mark_contacted",
                    description: "Record that the user caught up with someone (call, meetup, "
                        + "message). name is matched case-insensitively.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string", "minLength": 1],
                        ],
                        "required": ["name"],
                    ]
                ),
                spheres: [.relationships],
                confirmation: { input in
                    "Marked contact with \(input["name"]?.stringValue ?? "")"
                },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let name = input["name"]?.stringValue, !name.isEmpty else {
                        throw AgentToolInputError("name is required")
                    }
                    guard let contact = await self.contact(named: name) else {
                        let known = await self.contacts.map(\.name).joined(separator: ", ")
                        throw AgentToolInputError(
                            "Unknown contact \"\(name)\". Known: \(known.isEmpty ? "none yet" : known)"
                        )
                    }
                    try await self.markContacted(id: contact.id)
                    return JSONValue.object(["ok": true]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "get_relationships_summary",
                    description: "Look up the user's contacts: upcoming birthdays (with days "
                        + "left), who needs a check-in, and per-person notes. Use before "
                        + "discussing people, gifts, or staying in touch.",
                    inputSchema: ["type": "object", "properties": [:], "required": []]
                ),
                spheres: [.relationships],
                silent: true,
                handler: { [weak self] _ in
                    guard let self else { throw CancellationError() }
                    return await self.relationshipsSummaryJSON()
                }
            ),
        ]
    }

    private func contact(named name: String) -> Contact? {
        contacts.first { $0.name.lowercased() == name.lowercased() }
    }

    private func relationshipsSummaryJSON() -> String {
        JSONValue.object([
            "contacts": .array(contacts.map { contact in
                var fields: [String: JSONValue] = [
                    "name": .string(contact.name),
                    "type": .string(contact.type.rawValue),
                    "needsCheckin": .bool(contact.needsCheckin()),
                ]
                if let lastContact = contact.lastContact {
                    fields["lastContact"] = .string(DayKey.make(lastContact))
                }
                if !contact.note.isEmpty {
                    fields["note"] = .string(contact.note)
                }
                return .object(fields)
            }),
            "upcomingBirthdays": .array(upcomingBirthdays().map { contact in
                .object([
                    "name": .string(contact.name),
                    "daysUntil": .number(Double(contact.daysUntilBirthday() ?? 0)),
                ])
            }),
            "needsCheckin": .array(needsCheckin().map { .string($0.name) }),
        ]).encodedString()
    }
}

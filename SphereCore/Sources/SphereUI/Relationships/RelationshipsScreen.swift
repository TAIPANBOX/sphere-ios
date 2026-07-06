import SwiftUI
import SphereCore
#if canImport(UIKit)
import UIKit
#endif

public struct RelationshipsScreen: View {
    private let store: RelationshipsStore
    private let agent: AgentService?
    private let onConfigureProvider: (() -> Void)?
    @State private var showingAddContact = false
    @State private var selectedContact: Contact?
    @State private var showingImport = false
    @State private var importCandidates: [ImportedContact] = []
    @State private var loadingImport = false

    private let accent = SphereTheme.accent(for: .relationships)

    public init(
        store: RelationshipsStore,
        agent: AgentService? = nil,
        onConfigureProvider: (() -> Void)? = nil
    ) {
        self.store = store
        self.agent = agent
        self.onConfigureProvider = onConfigureProvider
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.contacts.isEmpty {
                    EmptyStateCard(
                        emoji: "💜",
                        accent: accent,
                        title: uiString("Start your Relationships sphere"),
                        message: uiString("Add someone you want to stay close to — a friend, family member, or mentor."),
                        buttonLabel: uiString("Add your first contact")
                    ) {
                        showingAddContact = true
                    }
                }
                if !store.upcomingBirthdays().isEmpty {
                    birthdaysCard
                }
                if !store.needsCheckin().isEmpty {
                    checkinSection
                }
                contactsSection
                templatesSection
            }
            .padding()
        }
        .navigationTitle(Text(ui: "Relationships"))
        .toolbar {
            if store.hasContactsProvider {
                Menu {
                    Button { showingAddContact = true } label: {
                        Label { Text(ui: "New contact") } icon: { Image(systemName: "plus") }
                    }
                    Button {
                        Task { await loadImportCandidates() }
                    } label: {
                        Label { Text(ui: "Import from Contacts") } icon: { Image(systemName: "person.crop.circle.badge.plus") }
                    }
                } label: {
                    if loadingImport {
                        ProgressView()
                    } else {
                        Image(systemName: "plus")
                    }
                }
            } else {
                Button {
                    showingAddContact = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddContact) {
            AddContactSheet { contact in
                Task { try? await store.add(contact) }
            }
        }
        .sheet(isPresented: $showingImport) {
            ContactPickerSheet(candidates: importCandidates) { selected in
                Task { await store.importContacts(selected) }
            }
        }
        .sheet(item: $selectedContact) { contact in
            ContactDetailSheet(
                store: store, contact: contact,
                agent: agent, onConfigureProvider: onConfigureProvider
            )
        }
        .task {
            try? await store.load()
        }
    }

    private func loadImportCandidates() async {
        loadingImport = true
        importCandidates = await store.importableContacts()
        loadingImport = false
        showingImport = true
    }

    // MARK: - Templates (More)

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui: "More").font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                MoreLink(uiString("Message templates"), systemImage: "text.bubble.fill",
                         count: store.templates.isEmpty ? nil : store.templates.count) { templatesList }
            }
            .sphereCard()
        }
    }

    private var templatesList: some View {
        CRUDListScreen(
            title: uiString("Message templates"),
            items: store.effectiveTemplates,
            emptyTitle: uiString("No templates"),
            emptySystemImage: "text.bubble",
            addSheet: { AddTemplateSheet { t in Task { try? await store.addTemplate(t) } } },
            row: { template in
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title).font(.body.weight(.medium))
                    Text(template.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            },
            onDelete: { t in Task { try? await store.removeTemplate(id: t.id) } },
            onRestore: { t in Task { try? await store.addTemplate(t) } }
        )
    }

    // MARK: - Birthdays

    private var birthdaysCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui: "🎂 Upcoming Birthdays").font(.headline)
            ForEach(store.upcomingBirthdays()) { contact in
                HStack {
                    Text(contact.emoji)
                    Text(contact.name).font(.body.weight(.medium))
                    Spacer()
                    if let days = contact.daysUntilBirthday() {
                        Text(days == 0 ? "Today! 🎉" : days == 1 ? "Tomorrow" : "in \(days) d")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(days <= 1 ? accent : .secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    // MARK: - Check-ins

    private var checkinSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui: "Time to reach out").font(.title3.weight(.semibold))
            ForEach(store.needsCheckin()) { contact in
                HStack(spacing: 12) {
                    Text(contact.emoji)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name).font(.body.weight(.medium))
                        Group {
                            if let lastContact = contact.lastContact {
                                Text(ui: "last contact \(lastContact, style: .relative) ago")
                            } else {
                                Text(ui: "never contacted")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { try? await store.markContacted(id: contact.id) }
                    } label: {
                        Text(ui: "Reached out")
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(accent)
                }
                .sphereCard()
            }
        }
    }

    // MARK: - Contacts

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui: "People").font(.title3.weight(.semibold))
            if store.contacts.isEmpty {
                Text(ui: "Add the people you want to stay close to.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(store.contacts) { contact in
                HStack(spacing: 12) {
                    Button {
                        selectedContact = contact
                    } label: {
                        HStack(spacing: 12) {
                            Text(contact.emoji).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name).font(.body.weight(.medium))
                                HStack(spacing: 6) {
                                    Text(contact.type.label)
                                    if !contact.note.isEmpty {
                                        Text("· \(contact.note)").lineLimit(1)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Menu {
                        Button {
                            Task { try? await store.markContacted(id: contact.id) }
                        } label: {
                            Text(ui: "Reached out")
                        }
                        Button(role: .destructive) {
                            Task { try? await store.remove(id: contact.id) }
                        } label: {
                            Text(ui: "Delete")
                        }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(.secondary)
                    }
                }
                .sphereCard()
            }
        }
    }
}

struct AddContactSheet: View {
    let onAdd: (Contact) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type = RelationshipType.friend
    @State private var note = ""
    @State private var hasBirthday = false
    @State private var birthday = Date()
    @State private var reminderDays = 30

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $name) { Text(ui: "Name") }
                Picker(selection: $type) {
                    ForEach(RelationshipType.allCases, id: \.self) { type in
                        Text("\(type.emoji) \(type.label)").tag(type)
                    }
                } label: { Text(ui: "Relationship") }
                TextField(text: $note) { Text(ui: "Note (optional)") }
                Toggle(isOn: $hasBirthday) { Text(ui: "Birthday") }
                if hasBirthday {
                    DatePicker(selection: $birthday, displayedComponents: .date) { Text(ui: "Date") }
                }
                Stepper(value: $reminderDays, in: 7...180, step: 7) { Text(ui: "Check in every \(reminderDays) d") }
            }
            .navigationTitle(Text(ui: "New Contact"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(Contact(
                            id: Contact.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            emoji: type.emoji,
                            type: type,
                            birthday: hasBirthday ? birthday : nil,
                            note: note,
                            reminderDays: reminderDays
                        ))
                        dismiss()
                    } label: {
                        Text(ui: "Add")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct ContactDetailSheet: View {
    let store: RelationshipsStore
    let contact: Contact
    var agent: AgentService? = nil
    var onConfigureProvider: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddDate = false
    @State private var showingBriefing = false
    @State private var copied = false

    private let accent = SphereTheme.accent(for: .relationships)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.prepFacts(for: contact.id), id: \.self) { fact in
                        Label(fact, systemImage: "sparkle").labelStyle(.titleAndIcon)
                    }
                    if agent != nil {
                        Button {
                            showingBriefing = true
                        } label: {
                            Label { Text(ui: "Prep me with the assistant") } icon: { Image(systemName: "sparkles") }
                        }
                    }
                } header: {
                    Label { Text(ui: "Prep — before you see \(contact.name)") } icon: { Image(systemName: "eyes") }
                }

                Section {
                    Button {
                        Task { try? await store.markContacted(id: contact.id) }
                    } label: {
                        Label { Text(ui: "Reached out today") } icon: { Image(systemName: "checkmark.circle.fill") }
                    }
                }

                Section {
                    ForEach(store.customDates(for: contact.id)) { date in
                        HStack {
                            Text(date.label)
                            Spacer()
                            if let days = date.daysUntil() {
                                Text("in \(days)d").foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button { showingAddDate = true } label: { Text(ui: "Add a date") }
                } header: {
                    Text(ui: "Dates")
                }

                if !contact.giftIdeas.isEmpty {
                    Section {
                        ForEach(contact.giftIdeas, id: \.self) { Text($0) }
                    } header: {
                        Text(ui: "Gift ideas")
                    }
                }

                Section {
                    ForEach(store.effectiveTemplates) { template in
                        Button {
                            copyToClipboard(template.body)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                Text(template.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                } header: {
                    copied ? Text(ui: "Copied!") : Text(ui: "Copy a message")
                }
            }
            .navigationTitle(contact.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button { dismiss() } label: { Text(ui: "Done") } }
            }
            .sheet(isPresented: $showingAddDate) {
                AddCustomDateSheet(contactId: contact.id) { date in
                    Task { try? await store.addCustomDate(date) }
                }
            }
            .sheet(isPresented: $showingBriefing) {
                AgentResultSheet(
                    title: uiString("Prep for \(contact.name)"),
                    systemImage: "person.text.rectangle",
                    tint: accent,
                    agent: agent,
                    task: .prepBriefing(contact: contact.name, facts: store.prepFacts(for: contact.id)),
                    onConfigureProvider: onConfigureProvider
                )
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #endif
        copied = true
    }
}

struct AddCustomDateSheet: View {
    let contactId: String
    let onAdd: (CustomDate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var date = Date()
    @State private var recurs = true

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $label) { Text(ui: "Label (e.g. Anniversary)") }
                DatePicker(selection: $date, displayedComponents: .date) { Text(ui: "Date") }
                Toggle(isOn: $recurs) { Text(ui: "Repeats yearly") }
            }
            .navigationTitle(Text(ui: "Add Date"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Text(ui: "Cancel") } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(CustomDate(
                            id: CustomDate.newID(),
                            contactId: contactId,
                            label: label.trimmingCharacters(in: .whitespaces),
                            date: date,
                            recursYearly: recurs
                        ))
                        dismiss()
                    } label: {
                        Text(ui: "Add")
                    }
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddTemplateSheet: View {
    let onAdd: (MessageTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $title) { Text(ui: "Title") }
                TextField(text: $message, axis: .vertical) { Text(ui: "Message") }
                    .lineLimit(3...8)
            }
            .navigationTitle(Text(ui: "Add Template"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Text(ui: "Cancel") } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(MessageTemplate(
                            id: MessageTemplate.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            body: message.trimmingCharacters(in: .whitespaces)
                        ))
                        dismiss()
                    } label: {
                        Text(ui: "Add")
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty
                        || message.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Multi-select list of importable device contacts.
struct ContactPickerSheet: View {
    let candidates: [ImportedContact]
    let onImport: ([ImportedContact]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>

    init(candidates: [ImportedContact], onImport: @escaping ([ImportedContact]) -> Void) {
        self.candidates = candidates
        self.onImport = onImport
        // Pre-select everyone — importing all is the common case.
        _selected = State(initialValue: Set(candidates.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.largeTitle).foregroundStyle(.secondary)
                        Text(ui: "Nothing new to import").font(.headline)
                        Text(ui: "Everyone in your contacts is already here, or access was denied.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                } else {
                    List {
                        Section {
                            ForEach(candidates) { candidate in
                                Button {
                                    toggle(candidate.id)
                                } label: {
                                    HStack {
                                        Image(systemName: selected.contains(candidate.id)
                                              ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected.contains(candidate.id)
                                                             ? SphereTheme.accent(for: .relationships) : .secondary)
                                        Text(candidate.name).foregroundStyle(.primary)
                                        Spacer()
                                        if candidate.birthday != nil {
                                            Image(systemName: "gift").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text(ui: "\(selected.count) of \(candidates.count) selected")
                        }
                    }
                }
            }
            .navigationTitle(Text(ui: "Import contacts"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onImport(candidates.filter { selected.contains($0.id) })
                        dismiss()
                    } label: {
                        Text(ui: "Import \(selected.count)")
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}

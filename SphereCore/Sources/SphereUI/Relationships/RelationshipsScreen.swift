import SwiftUI
import SphereCore

public struct RelationshipsScreen: View {
    private let store: RelationshipsStore
    @State private var showingAddContact = false

    private let accent = SphereTheme.accent(for: .relationships)

    public init(store: RelationshipsStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !store.upcomingBirthdays().isEmpty {
                    birthdaysCard
                }
                if !store.needsCheckin().isEmpty {
                    checkinSection
                }
                contactsSection
            }
            .padding()
        }
        .navigationTitle("Relationships")
        .toolbar {
            Button {
                showingAddContact = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddContact) {
            AddContactSheet { contact in
                Task { try? await store.add(contact) }
            }
        }
        .task {
            try? await store.load()
        }
    }

    // MARK: - Birthdays

    private var birthdaysCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🎂 Upcoming Birthdays").font(.headline)
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
            Text("Time to reach out").font(.title3.weight(.semibold))
            ForEach(store.needsCheckin()) { contact in
                HStack(spacing: 12) {
                    Text(contact.emoji)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name).font(.body.weight(.medium))
                        Text(
                            contact.lastContact.map { "last contact \($0, style: .relative) ago" }
                                ?? "never contacted"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reached out") {
                        Task { try? await store.markContacted(id: contact.id) }
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
            Text("People").font(.title3.weight(.semibold))
            if store.contacts.isEmpty {
                Text("Add the people you want to stay close to.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(store.contacts) { contact in
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
                    Menu {
                        Button("Reached out") {
                            Task { try? await store.markContacted(id: contact.id) }
                        }
                        Button("Delete", role: .destructive) {
                            Task { try? await store.remove(id: contact.id) }
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
                TextField("Name", text: $name)
                Picker("Relationship", selection: $type) {
                    ForEach(RelationshipType.allCases, id: \.self) { type in
                        Text("\(type.emoji) \(type.label)").tag(type)
                    }
                }
                TextField("Note (optional)", text: $note)
                Toggle("Birthday", isOn: $hasBirthday)
                if hasBirthday {
                    DatePicker("Date", selection: $birthday, displayedComponents: .date)
                }
                Stepper("Check in every \(reminderDays) d", value: $reminderDays, in: 7...180, step: 7)
            }
            .navigationTitle("New Contact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
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
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

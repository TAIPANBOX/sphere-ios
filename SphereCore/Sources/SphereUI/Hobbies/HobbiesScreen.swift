import SwiftUI
import SphereCore

public struct HobbiesScreen: View {
    private let store: HobbiesStore
    @State private var showingAddHobby = false
    @State private var showingLogSession = false

    private let accent = SphereTheme.accent(for: .hobbies)

    public init(store: HobbiesStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                weeklyCard
                hobbiesSection
                sessionsSection
            }
            .padding()
        }
        .navigationTitle("Hobbies")
        .toolbar {
            Menu {
                Button("Log Session") { showingLogSession = true }
                Button("Add Hobby") { showingAddHobby = true }
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddHobby) {
            AddHobbySheet { hobby in
                Task { try? await store.addHobby(hobby) }
            }
        }
        .sheet(isPresented: $showingLogSession) {
            LogHobbySessionSheet(hobbies: store.hobbies) { session in
                Task { try? await store.logSession(session) }
            }
        }
        .task {
            try? await store.load()
        }
    }

    // MARK: - Weekly summary

    private var weeklyCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("This Week").font(.headline)
                Text("across \(store.hobbies.count) hobbies")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(store.totalWeeklyMinutes()) min")
                .font(.title2.weight(.bold))
                .foregroundStyle(accent)
        }
        .sphereCard()
    }

    // MARK: - Hobbies

    private var hobbiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My Hobbies").font(.title3.weight(.semibold))
            if store.hobbies.isEmpty {
                Text("Add a hobby to start tracking time for it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(store.hobbies) { hobby in
                let weekly = store.weeklyMinutes(for: hobby.id)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(hobby.emoji)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hobby.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(hobby.isActive ? .primary : .secondary)
                            Text("\(weekly) / \(hobby.targetMinutesPerWeek) min · \(hobby.frequency.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button(hobby.isActive ? "Pause" : "Resume") {
                                Task { try? await store.toggleActive(id: hobby.id) }
                            }
                            Button("Delete", role: .destructive) {
                                Task { try? await store.removeHobby(id: hobby.id) }
                            }
                        } label: {
                            Image(systemName: "ellipsis").foregroundStyle(.secondary)
                        }
                    }
                    ProgressView(
                        value: Double(min(weekly, hobby.targetMinutesPerWeek)),
                        total: Double(max(hobby.targetMinutesPerWeek, 1))
                    )
                    .tint(weekly >= hobby.targetMinutesPerWeek ? .green : accent)
                    if !hobby.goal.isEmpty {
                        Text("🎯 \(hobby.goal)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .sphereCard()
            }
        }
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Sessions").font(.title3.weight(.semibold))
            ForEach(store.sessions.prefix(10)) { session in
                HStack(spacing: 12) {
                    Text(store.hobbies.first { $0.id == session.hobbyId }?.emoji ?? "✨")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.hobbies.first { $0.id == session.hobbyId }?.name ?? "Hobby")
                            .font(.body.weight(.medium))
                        if !session.note.isEmpty {
                            Text(session.note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(session.durationMinutes) min")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                        Text(session.date, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .sphereCard()
            }
        }
    }
}

struct AddHobbySheet: View {
    let onAdd: (Hobby) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🎸"
    @State private var frequency = HobbyFrequency.weekly
    @State private var target = 60

    var body: some View {
        NavigationStack {
            Form {
                TextField("Hobby", text: $name)
                TextField("Emoji", text: $emoji)
                Picker("Frequency", selection: $frequency) {
                    ForEach(HobbyFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.label).tag(frequency)
                    }
                }
                Stepper("Target: \(target) min/week", value: $target, in: 15...840, step: 15)
            }
            .navigationTitle("New Hobby")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(Hobby(
                            id: Hobby.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            emoji: emoji.isEmpty ? "🎸" : emoji,
                            frequency: frequency,
                            targetMinutesPerWeek: target
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct LogHobbySessionSheet: View {
    let hobbies: [Hobby]
    let onLog: (HobbySession) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hobbyId: String?
    @State private var minutes = 30
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Hobby", selection: $hobbyId) {
                    ForEach(hobbies) { hobby in
                        Text("\(hobby.emoji) \(hobby.name)").tag(Optional(hobby.id))
                    }
                }
                Stepper("\(minutes) minutes", value: $minutes, in: 5...720, step: 5)
                TextField("Note (optional)", text: $note)
            }
            .navigationTitle("Log Session")
            .onAppear {
                if hobbyId == nil { hobbyId = hobbies.first?.id }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let hobbyId {
                            onLog(HobbySession(
                                id: HobbySession.newID(),
                                hobbyId: hobbyId,
                                durationMinutes: minutes,
                                date: Date(),
                                note: note
                            ))
                        }
                        dismiss()
                    }
                    .disabled(hobbyId == nil)
                }
            }
        }
    }
}

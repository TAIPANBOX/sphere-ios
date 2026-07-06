import SwiftUI
import SphereCore

public struct HobbiesScreen: View {
    private let store: HobbiesStore
    @State private var showingAddHobby = false
    @State private var showingLogSession = false
    @State private var selectedHobby: Hobby?

    private let accent = SphereTheme.accent(for: .hobbies)

    public init(store: HobbiesStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.hobbies.isEmpty {
                    EmptyStateCard(
                        emoji: "🎸",
                        accent: accent,
                        title: uiString("Start your Hobbies sphere"),
                        message: uiString("Add something you do for the joy of it, and start making time for it."),
                        buttonLabel: uiString("Add your first hobby")
                    ) {
                        showingAddHobby = true
                    }
                }
                weeklyCard
                hobbiesSection
                sessionsSection
            }
            .padding()
        }
        .navigationTitle(Text(ui: "Hobbies"))
        .toolbar {
            Menu {
                Button { showingLogSession = true } label: { Text(ui: "Log Session") }
                Button { showingAddHobby = true } label: { Text(ui: "Add Hobby") }
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
        .sheet(item: $selectedHobby) { hobby in
            HobbyDetailSheet(store: store, hobby: hobby)
        }
        .task {
            try? await store.load()
        }
    }

    // MARK: - Weekly summary

    private var weeklyCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ui: "This Week").font(.headline)
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
            Text(ui: "My Hobbies").font(.title3.weight(.semibold))
            if store.hobbies.isEmpty {
                Text(ui: "Add a hobby to start tracking time for it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(store.hobbies) { hobby in
                let weekly = store.weeklyMinutes(for: hobby.id)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button {
                            selectedHobby = hobby
                        } label: {
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
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Menu {
                            Button {
                                Task { try? await store.toggleActive(id: hobby.id) }
                            } label: {
                                hobby.isActive ? Text(ui: "Pause") : Text(ui: "Resume")
                            }
                            Button(role: .destructive) {
                                Task { try? await store.removeHobby(id: hobby.id) }
                            } label: {
                                Text(ui: "Delete")
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
                    HStack(spacing: 12) {
                        if let cost = store.costPerSession(for: hobby.id) {
                            Text("💸 \(Int(cost))/session").font(.caption2).foregroundStyle(.secondary)
                        }
                        if let rating = store.averageRating(for: hobby.id) {
                            Text(String(format: "⭐ %.1f", rating)).font(.caption2).foregroundStyle(.secondary)
                        }
                        if !hobby.goal.isEmpty {
                            Text("🎯 \(hobby.goal)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .sphereCard()
            }
        }
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui: "Recent Sessions").font(.title3.weight(.semibold))
            ForEach(store.sessions.prefix(10)) { session in
                HStack(spacing: 12) {
                    Text(store.hobbies.first { $0.id == session.hobbyId }?.emoji ?? "✨")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.hobbies.first { $0.id == session.hobbyId }?.name ?? uiString("Hobby"))
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
                TextField(text: $name) { Text(ui: "Hobby") }
                TextField(text: $emoji) { Text(ui: "Emoji") }
                Picker("Frequency", selection: $frequency) {
                    ForEach(HobbyFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.label).tag(frequency)
                    }
                }
                Stepper("Target: \(target) min/week", value: $target, in: 15...840, step: 15)
            }
            .navigationTitle(Text(ui: "New Hobby"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(Hobby(
                            id: Hobby.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            emoji: emoji.isEmpty ? "🎸" : emoji,
                            frequency: frequency,
                            targetMinutesPerWeek: target
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

struct LogHobbySessionSheet: View {
    let hobbies: [Hobby]
    let onLog: (HobbySession) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hobbyId: String?
    @State private var minutes = 30
    @State private var note = ""
    @State private var rating = 0

    var body: some View {
        NavigationStack {
            Form {
                Picker("Hobby", selection: $hobbyId) {
                    ForEach(hobbies) { hobby in
                        Text("\(hobby.emoji) \(hobby.name)").tag(Optional(hobby.id))
                    }
                }
                Stepper("\(minutes) minutes", value: $minutes, in: 5...720, step: 5)
                HStack {
                    Text(ui: "Enjoyment")
                    Spacer()
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .foregroundStyle(.yellow)
                            .onTapGesture { rating = (rating == star) ? 0 : star }
                    }
                }
                TextField(text: $note) { Text(ui: "Note (optional)") }
            }
            .navigationTitle(Text(ui: "Log Session"))
            .onAppear {
                if hobbyId == nil { hobbyId = hobbies.first?.id }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let hobbyId {
                            onLog(HobbySession(
                                id: HobbySession.newID(),
                                hobbyId: hobbyId,
                                durationMinutes: minutes,
                                date: Date(),
                                note: note,
                                rating: rating
                            ))
                        }
                        dismiss()
                    } label: {
                        Text(ui: "Save")
                    }
                    .disabled(hobbyId == nil)
                }
            }
        }
    }
}

struct HobbyDetailSheet: View {
    let store: HobbiesStore
    let hobby: Hobby
    @Environment(\.dismiss) private var dismiss
    @State private var newMilestone = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Total time", value: "\(store.totalMinutes(for: hobby.id)) min")
                    if let cost = store.costPerSession(for: hobby.id) {
                        LabeledContent("Cost per session", value: "\(Int(cost))")
                    }
                    if let rating = store.averageRating(for: hobby.id) {
                        LabeledContent("Avg enjoyment", value: String(format: "%.1f / 5", rating))
                    }
                } header: {
                    Text(ui: "Stats")
                }

                Section {
                    ForEach(store.milestones(for: hobby.id)) { milestone in
                        Button {
                            Task { try? await store.toggleMilestone(id: milestone.id) }
                        } label: {
                            HStack {
                                Image(systemName: milestone.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(milestone.done ? .green : .secondary)
                                Text(milestone.title)
                                    .strikethrough(milestone.done)
                                    .foregroundStyle(milestone.done ? .secondary : .primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    HStack {
                        TextField(text: $newMilestone) { Text(ui: "New milestone (e.g. Play a full song)") }
                        Button {
                            let title = newMilestone.trimmingCharacters(in: .whitespaces)
                            newMilestone = ""
                            Task {
                                try? await store.addMilestone(HobbyMilestone(
                                    id: HobbyMilestone.newID(), hobbyId: hobby.id, title: title
                                ))
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newMilestone.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text(ui: "Milestones")
                }
            }
            .navigationTitle(hobby.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button { dismiss() } label: { Text(ui: "Done") } }
            }
        }
    }
}

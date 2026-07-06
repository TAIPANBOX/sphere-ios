import SwiftUI
import SphereCore

/// Golden-template sphere screen. The pattern every sphere screen follows:
/// a store injected from the composition root, `.task { load() }`, sections
/// as cards, mutations through async store methods, add-flows as sheets.
public struct GoalsScreen: View {
    private let store: GoalsStore
    private let agent: AgentService?
    private let onConfigureProvider: (() -> Void)?
    @State private var showingAddGoal = false
    @State private var showingAddHabit = false
    @State private var showingAddAntiGoal = false
    @State private var breakdownGoal: Goal?

    private let accent = SphereTheme.accent(for: .goals)

    public init(
        store: GoalsStore,
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
                if store.goals.isEmpty && store.habits.isEmpty {
                    EmptyStateCard(
                        emoji: "🎯",
                        accent: accent,
                        title: "Start your Goals sphere",
                        message: "Pick one goal that matters right now — you can always break it down later.",
                        buttonLabel: "Add your first goal"
                    ) {
                        showingAddGoal = true
                    }
                }

                lifeProgressCard

                section(title: "Active Goals") {
                    if activeGoals.isEmpty {
                        emptyState("No goals yet. Add one — or just tell your agent.")
                    }
                    ForEach(activeGoals) { goal in
                        GoalCard(
                            goal: goal, accent: accent,
                            onBreakDown: agent != nil ? { breakdownGoal = goal } : nil
                        ) { percent in
                            Task { try? await store.setProgress(id: goal.id, percent: percent) }
                        } onTogglePause: {
                            Task { try? await store.toggleStatus(id: goal.id) }
                        } onDelete: {
                            Task { try? await store.remove(id: goal.id) }
                        }
                    }
                }

                if !completedGoals.isEmpty {
                    section(title: "Completed") {
                        ForEach(completedGoals) { goal in
                            HStack {
                                Text(goal.emoji)
                                Text(goal.title).strikethrough()
                                Spacer()
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                            .sphereCard()
                        }
                    }
                }

                section(title: "Habits") {
                    if store.habits.isEmpty {
                        emptyState("Track a daily habit and build a streak.")
                    }
                    ForEach(store.habits) { habit in
                        HabitRow(habit: habit, accent: accent) {
                            Task { try? await store.toggleHabit(id: habit.id) }
                        }
                    }
                }

                antiGoalsSection
            }
            .padding()
        }
        .navigationTitle("Goals")
        .toolbar {
            Menu {
                Button("Add Goal") { showingAddGoal = true }
                Button("Add Habit") { showingAddHabit = true }
                Button("Add Anti-goal") { showingAddAntiGoal = true }
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddGoal) {
            AddGoalSheet { goal in
                Task { try? await store.add(goal) }
            }
        }
        .sheet(isPresented: $showingAddHabit) {
            AddHabitSheet { habit in
                Task { try? await store.addHabit(habit) }
            }
        }
        .sheet(isPresented: $showingAddAntiGoal) {
            AddAntiGoalSheet { antiGoal in
                Task { try? await store.addAntiGoal(antiGoal) }
            }
        }
        .sheet(item: $breakdownGoal) { goal in
            AgentResultSheet(
                title: "Break it down",
                subtitle: goal.title,
                systemImage: "list.bullet.rectangle",
                tint: accent,
                agent: agent,
                task: .decomposeGoal(title: goal.title, why: goal.why),
                onConfigureProvider: onConfigureProvider
            )
        }
        .task {
            try? await store.load()
        }
    }

    private var antiGoalsSection: some View {
        section(title: "Anti-goals") {
            if store.antiGoals.isEmpty {
                emptyState("What will you say no to? Boundaries free your focus.")
            }
            ForEach(store.antiGoals) { antiGoal in
                HStack(spacing: 10) {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(antiGoal.title).font(.body.weight(.medium))
                        if !antiGoal.note.isEmpty {
                            Text(antiGoal.note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        Task { try? await store.removeAntiGoal(id: antiGoal.id) }
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .sphereCard()
            }
        }
    }

    private var activeGoals: [Goal] {
        store.goals.filter { $0.status != .completed }
    }

    private var completedGoals: [Goal] {
        store.goals.filter { $0.status == .completed }
    }

    private var lifeProgressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overall Life Progress")
                .font(.headline)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(store.overallProgress)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                Text("%").font(.title3).foregroundStyle(.secondary)
                Spacer()
                Text("\(activeGoals.count) active")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(store.overallProgress), total: 100)
                .tint(accent)
        }
        .sphereCard()
    }

    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sphereCard()
    }
}

struct GoalCard: View {
    let goal: Goal
    let accent: Color
    var onBreakDown: (() -> Void)? = nil
    let onProgress: (Int) -> Void
    let onTogglePause: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(goal.emoji)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title).font(.body.weight(.medium))
                    Text(goal.horizon.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if goal.status == .paused {
                    Text("Paused")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Menu {
                    if let onBreakDown {
                        Button("Break this down", systemImage: "sparkles", action: onBreakDown)
                    }
                    Button(goal.status == .paused ? "Resume" : "Pause", action: onTogglePause)
                    Button("+10% progress") { onProgress(goal.progressPercent + 10) }
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(goal.progressPercent), total: 100)
                .tint(goal.status == .paused ? .secondary : accent)
            HStack {
                Text("\(Momentum.forProgress(goal.progressPercent).emoji) \(Momentum.progressPhrase(goal.progressPercent))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accent)
                Spacer()
                Text("\(goal.progressPercent)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !goal.keyResults.isEmpty {
                Text("\(goal.keyResults.count) key results")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // Resurface the "why" while the goal is stalled.
            if goal.progressPercent < 20, !goal.why.isEmpty {
                Text("💭 Remember why: \(goal.why)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sphereCard()
    }
}

struct HabitRow: View {
    let habit: Habit
    let accent: Color
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(habit.emoji)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                    if !habit.identity.isEmpty {
                        Text("A vote for \(habit.identity)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if habit.streak() > 0 {
                    Label("\(habit.streak())", systemImage: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Button(action: onToggle) {
                    Image(systemName: habit.checkedIn() ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(habit.checkedIn() ? accent : .secondary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 3) {
                ForEach(Array(habit.heatmap(days: 21).enumerated()), id: \.offset) { _, done in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(done ? accent : Color.secondary.opacity(0.15))
                        .frame(height: 12)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .sphereCard()
    }
}

struct AddGoalSheet: View {
    let onAdd: (Goal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var emoji = "🎯"
    @State private var horizon = GoalHorizon.year
    @State private var why = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Goal title", text: $title)
                TextField("Description (optional)", text: $details)
                TextField("Emoji", text: $emoji)
                Picker("Horizon", selection: $horizon) {
                    ForEach(GoalHorizon.allCases, id: \.self) { horizon in
                        Text(horizon.label).tag(horizon)
                    }
                }
                Section {
                    TextField("Why does this matter?", text: $why, axis: .vertical).lineLimit(2...4)
                } footer: {
                    Text("Your reason is resurfaced whenever the goal stalls.")
                }
            }
            .navigationTitle("New Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(Goal(
                            id: Goal.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            description: details,
                            emoji: emoji.isEmpty ? "🎯" : emoji,
                            horizon: horizon,
                            why: why.trimmingCharacters(in: .whitespaces)
                        ))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddHabitSheet: View {
    let onAdd: (Habit) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "✅"
    @State private var identity = ""
    @State private var weekdays: Set<Int> = []

    private let dayLabels = [(1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Habit (e.g. Read 10 pages)", text: $name)
                TextField("Emoji", text: $emoji)
                Section {
                    TextField("I am… (e.g. a reader)", text: $identity)
                } header: {
                    Text("Identity")
                } footer: {
                    Text("Each check-in is a vote for who you're becoming.")
                }
                Section("Remind me on") {
                    HStack(spacing: 6) {
                        ForEach(dayLabels, id: \.0) { day, label in
                            Button {
                                if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                            } label: {
                                Text(label)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .background(
                                        weekdays.contains(day) ? Color.accentColor : Color.secondary.opacity(0.12),
                                        in: Circle()
                                    )
                                    .foregroundStyle(weekdays.contains(day) ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("New Habit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(Habit(
                            id: Habit.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            emoji: emoji.isEmpty ? "✅" : emoji,
                            identity: identity.trimmingCharacters(in: .whitespaces),
                            reminderWeekdays: weekdays.sorted()
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddAntiGoalSheet: View {
    let onAdd: (AntiGoal) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What will you say no to?", text: $title)
                    TextField("Why (optional)", text: $note, axis: .vertical).lineLimit(2...4)
                } footer: {
                    Text("A boundary, not a target — clarity on what you won't do.")
                }
            }
            .navigationTitle("New Anti-goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(AntiGoal(
                            id: AntiGoal.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            note: note.trimmingCharacters(in: .whitespaces)
                        ))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

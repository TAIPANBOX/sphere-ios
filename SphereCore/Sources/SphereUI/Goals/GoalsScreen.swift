import SwiftUI
import SphereCore

/// Golden-template sphere screen. The pattern every sphere screen follows:
/// a store injected from the composition root, `.task { load() }`, sections
/// as cards, mutations through async store methods, add-flows as sheets.
public struct GoalsScreen: View {
    private let store: GoalsStore
    @State private var showingAddGoal = false

    private let accent = SphereTheme.accent(for: .goals)

    public init(store: GoalsStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                lifeProgressCard

                section(title: "Active Goals") {
                    if activeGoals.isEmpty {
                        emptyState("No goals yet. Add one — or just tell your agent.")
                    }
                    ForEach(activeGoals) { goal in
                        GoalCard(goal: goal, accent: accent) { percent in
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
            }
            .padding()
        }
        .navigationTitle("Goals")
        .toolbar {
            Button {
                showingAddGoal = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddGoal) {
            AddGoalSheet { goal in
                Task { try? await store.add(goal) }
            }
        }
        .task {
            try? await store.load()
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
                Text("\(goal.progressPercent)%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer()
                if !goal.keyResults.isEmpty {
                    Text("\(goal.keyResults.count) key results")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        HStack(spacing: 12) {
            Text(habit.emoji)
            Text(habit.name)
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
                            horizon: horizon
                        ))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

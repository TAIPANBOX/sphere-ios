import SwiftUI
import Charts
import SphereCore

public struct RestScreen: View {
    private let store: RestStore
    /// Today's stress level (0–10) from the mindfulness sphere, once ported.
    private let stressLevel: Int?
    /// Annual paid-time-off allowance from the profile (drives the ledger).
    private let vacationAllowance: Int?
    @State private var showingLogSleep = false
    @State private var importing = false
    @State private var importResult: String?

    private let accent = SphereTheme.accent(for: .rest)

    public init(store: RestStore, stressLevel: Int? = nil, vacationAllowance: Int? = nil) {
        self.store = store
        self.stressLevel = stressLevel
        self.vacationAllowance = vacationAllowance
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.sleepEntries.isEmpty {
                    EmptyStateCard(
                        emoji: "🌊",
                        accent: accent,
                        title: "Start your Rest sphere",
                        message: "Log last night's sleep to see your recovery score and debt build up here.",
                        buttonLabel: "Log your first night's sleep"
                    ) {
                        showingLogSleep = true
                    }
                }
                recoveryCard
                if store.sleepDebtLast7() >= 1 {
                    sleepDebtCard
                }
                sleepChartCard
                if store.hasHealthProvider {
                    healthImportRow
                }
                scheduleCard
                if let allowance = vacationAllowance {
                    vacationCard(allowance: allowance)
                }
                detoxCard
                burnoutCard
                weekendCard
                moreSection
                sleepLogSection
            }
            .padding()
        }
        .navigationTitle("Rest")
        .toolbar {
            Button {
                showingLogSleep = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingLogSleep) {
            LogSleepSheet { entry in
                Task { try? await store.add(entry) }
            }
        }
        .task {
            try? await store.load()
            await autoImport()
        }
    }

    private var healthImportRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill").font(.title3).foregroundStyle(.pink)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Health").font(.subheadline.weight(.medium))
                Text(importResult ?? "Import last nights' sleep automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if importing {
                ProgressView()
            } else {
                Button("Import") {
                    Task { await runImport() }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    private func autoImport() async {
        guard store.hasHealthProvider else { return }
        let added = await store.importSleepFromHealth(days: 30)
        if added > 0 { importResult = "Added \(added) night\(added == 1 ? "" : "s")." }
    }

    private func runImport() async {
        importing = true
        let added = await store.importSleepFromHealth(days: 30)
        importResult = added > 0
            ? "Added \(added) night\(added == 1 ? "" : "s")."
            : "You're up to date."
        importing = false
    }

    // MARK: - Sleep debt (gem)

    private var sleepDebtCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill").font(.title2).foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1fh sleep debt", store.sleepDebtLast7()))
                    .font(.headline)
                Text("Deficit over the last 7 nights vs your goal. An extra "
                    + "early night helps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    // MARK: - Vacation ledger (gem)

    private func vacationCard(allowance: Int) -> some View {
        let used = store.usedVacationDays()
        let remaining = store.remainingVacationDays(allowance: allowance)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Time off this year", systemImage: "beach.umbrella.fill")
                    .font(.headline).foregroundStyle(accent)
                Spacer()
                Text("\(remaining) of \(allowance) left")
                    .font(.subheadline.weight(.semibold))
            }
            ProgressView(value: Double(used), total: Double(max(allowance, 1))).tint(accent)
            Button {
                Task { try? await store.toggleVacation() }
            } label: {
                Label(store.isVacationDay() ? "Today is marked off" : "Mark today as time off",
                      systemImage: store.isVacationDay() ? "checkmark.circle.fill" : "plus.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
        }
        .sphereCard()
    }

    // MARK: - More (naps, recovery menu)

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("More").font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                MoreLink("Naps", systemImage: "powersleep",
                         count: store.naps.isEmpty ? nil : store.naps.count) { napsList }
                Divider().padding(.leading, 38)
                MoreLink("What restores me", systemImage: "leaf.fill",
                         count: store.recoveryActivities.isEmpty ? nil : store.recoveryActivities.count) { recoveryList }
            }
            .sphereCard()
        }
    }

    private var napsList: some View {
        CRUDListScreen(
            title: "Naps",
            items: store.naps,
            emptyTitle: "No naps logged",
            emptySystemImage: "powersleep",
            addSheet: { AddNapSheet { nap in Task { try? await store.addNap(nap) } } },
            row: { nap in
                HStack {
                    Text("\(nap.minutes) min").font(.body.weight(.medium))
                    Spacer()
                    Text(nap.date, style: .date).font(.caption).foregroundStyle(.secondary)
                }
            },
            onDelete: { nap in Task { try? await store.removeNap(id: nap.id) } },
            onRestore: { nap in Task { try? await store.addNap(nap) } }
        )
    }

    private var recoveryList: some View {
        CRUDListScreen(
            title: "What restores me",
            items: store.recoveryActivities,
            emptyTitle: "Nothing added yet",
            emptySystemImage: "leaf",
            addSheet: { AddRecoveryActivitySheet { a in Task { try? await store.addRecoveryActivity(a) } } },
            row: { activity in
                HStack(spacing: 10) {
                    Text(activity.emoji)
                    Text(activity.name).font(.body.weight(.medium))
                    Spacer()
                    Text(String(repeating: "●", count: activity.rating))
                        .font(.caption).foregroundStyle(accent)
                }
            },
            onDelete: { activity in Task { try? await store.removeRecoveryActivity(id: activity.id) } },
            onRestore: { activity in Task { try? await store.addRecoveryActivity(activity) } }
        )
    }

    // MARK: - Recovery

    private var recoveryCard: some View {
        let score = store.recoveryScore(stressLevel: stressLevel)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Recovery Score").font(.headline)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(score)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(score))
                Text(scoreLabel(score))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(scoreEmoji(score)).font(.system(size: 36))
            }
            ProgressView(value: Double(score), total: 100)
                .tint(scoreColor(score))
            Text("Based on 7-day sleep vs 8h goal"
                + (stressLevel != nil ? " and today's stress" : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sphereCard()
    }

    private func scoreLabel(_ score: Int) -> String {
        if score >= 80 { return "Excellent" }
        if score >= 60 { return "Good" }
        if score >= 40 { return "Fair" }
        return "Poor"
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return accent }
        if score >= 40 { return .orange }
        return .red
    }

    private func scoreEmoji(_ score: Int) -> String {
        if score >= 80 { return "✨" }
        if score >= 60 { return "🙂" }
        if score >= 40 { return "😐" }
        return "😴"
    }

    // MARK: - Sleep chart

    private var sleepChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sleep, last 7 days").font(.headline)
                Spacer()
                Text(String(format: "avg %.1fh", store.avgHoursLast7()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(store.last7().reversed()) { entry in
                    BarMark(
                        x: .value("Day", DayKey.make(entry.date)),
                        y: .value("Hours", entry.hoursSlept)
                    )
                    .foregroundStyle(accent)
                    .cornerRadius(4)
                }
                RuleMark(y: .value("Goal", store.schedule.goalHours))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.secondary)
            }
            .chartXAxis(.hidden)
            .frame(height: 140)
        }
        .sphereCard()
    }

    // MARK: - Schedule

    private var scheduleCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label("Bedtime", systemImage: "moon.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.schedule.bedtimeLabel).font(.title3.weight(.semibold))
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Label("Wake", systemImage: "sun.max.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.schedule.wakeLabel).font(.title3.weight(.semibold))
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("Scheduled").font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.1fh", store.schedule.scheduledHours))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
            }
        }
        .sphereCard()
    }

    // MARK: - Detox & burnout

    private var detoxCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Digital Detox").font(.headline)
                Text(store.detoxStreak() > 0 ? "\(store.detoxStreak())-day streak 🔥" : "No streak yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { store.isDetoxDay() },
                set: { _ in Task { try? await store.toggleDetox() } }
            ))
            .labelsHidden()
        }
        .sphereCard()
    }

    private var burnoutCard: some View {
        let weekly = store.weeklyWorkHours()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Anti-Burnout").font(.headline)
                Spacer()
                Text(String(format: "%.0fh this week", weekly))
                    .font(.subheadline)
                    .foregroundStyle(weekly > 50 ? .red : .secondary)
            }
            ProgressView(value: min(weekly, 60), total: 60)
                .tint(weekly > 50 ? .red : accent)
            Text("Keep the work week under 50h")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sphereCard()
    }

    // MARK: - Weekend

    private var weekendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekend Plans").font(.headline)
            let plan = store.currentWeekendPlan()
            if let plan, !plan.activities.isEmpty {
                ForEach(Array(plan.activities.enumerated()), id: \.offset) { index, activity in
                    HStack {
                        Text("· \(activity)")
                        Spacer()
                        Button {
                            Task { try? await store.removeWeekendActivity(at: index) }
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("Nothing planned yet — dream a little.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    // MARK: - Sleep log

    private var sleepLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sleep Log").font(.title3.weight(.semibold))
            ForEach(store.sleepEntries.prefix(10)) { entry in
                HStack(spacing: 12) {
                    Text(entry.recovery.emoji)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.1fh · %@", entry.hoursSlept, entry.recovery.label))
                            .font(.body.weight(.medium))
                        if !entry.note.isEmpty {
                            Text(entry.note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(entry.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .sphereCard()
            }
        }
    }
}

struct LogSleepSheet: View {
    let onLog: (SleepEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hours = 8.0
    @State private var recovery = RecoveryLevel.good
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Stepper(String(format: "Slept %.1f hours", hours), value: $hours, in: 0...14, step: 0.5)
                Picker("Felt", selection: $recovery) {
                    ForEach(RecoveryLevel.allCases, id: \.self) { level in
                        Text("\(level.emoji) \(level.label)").tag(level)
                    }
                }
                TextField("Note (optional)", text: $note)
            }
            .navigationTitle("Log Sleep")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onLog(SleepEntry(
                            id: SleepEntry.newID(),
                            date: Date(),
                            hoursSlept: hours,
                            recovery: recovery,
                            note: note
                        ))
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AddNapSheet: View {
    let onAdd: (Nap) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 20

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Duration: \(minutes) min", value: $minutes, in: 5...180, step: 5)
            }
            .navigationTitle("Log Nap")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(Nap(id: Nap.newID(), date: Date(), minutes: minutes))
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AddRecoveryActivitySheet: View {
    let onAdd: (RecoveryActivity) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🌿"
    @State private var rating = 3

    var body: some View {
        NavigationStack {
            Form {
                TextField("Activity (e.g. a long walk)", text: $name)
                TextField("Emoji", text: $emoji)
                Stepper("How restorative: \(rating)/5", value: $rating, in: 1...5)
            }
            .navigationTitle("Add Activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(RecoveryActivity(
                            id: RecoveryActivity.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            emoji: emoji.isEmpty ? "🌿" : String(emoji.prefix(2)),
                            rating: rating
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

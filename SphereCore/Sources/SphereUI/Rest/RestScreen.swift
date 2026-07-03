import SwiftUI
import Charts
import SphereCore

public struct RestScreen: View {
    private let store: RestStore
    /// Today's stress level (0–10) from the mindfulness sphere, once ported.
    private let stressLevel: Int?
    @State private var showingLogSleep = false

    private let accent = SphereTheme.accent(for: .rest)

    public init(store: RestStore, stressLevel: Int? = nil) {
        self.store = store
        self.stressLevel = stressLevel
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                recoveryCard
                sleepChartCard
                scheduleCard
                detoxCard
                burnoutCard
                weekendCard
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
        }
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

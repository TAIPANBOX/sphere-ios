import SwiftUI
import Charts
import SphereCore

public struct HealthScreen: View {
    private let store: HealthStore
    /// From the user profile; drives the BMI card.
    private let heightCm: Double?
    @State private var showingLogWeight = false
    @State private var showingAddWorkout = false

    private let accent = SphereTheme.accent(for: .health)

    public init(store: HealthStore, heightCm: Double? = nil) {
        self.store = store
        self.heightCm = heightCm
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                metricsGrid
                stepsChartCard
                waterCard
                weightCard
                workoutsSection
            }
            .padding()
        }
        .navigationTitle("Health")
        .sheet(isPresented: $showingLogWeight) {
            LogWeightSheet { kg in
                Task { try? await store.logWeight(kg: kg) }
            }
        }
        .sheet(isPresented: $showingAddWorkout) {
            AddWorkoutSheet { workout in
                Task { try? await store.addWorkout(workout) }
            }
        }
        .task {
            try? await store.load()
            await store.refreshMetrics()
        }
    }

    // MARK: - Metrics

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: "Steps", value: "\(store.metrics.steps)", icon: "figure.walk", tint: accent)
            MetricCard(
                title: "Heart Rate",
                value: store.metrics.heartRate > 0 ? "\(Int(store.metrics.heartRate)) bpm" : "—",
                icon: "heart.fill", tint: .red
            )
            MetricCard(
                title: "Sleep",
                value: store.metrics.sleepHours > 0
                    ? String(format: "%.1f h", store.metrics.sleepHours) : "—",
                icon: "bed.double.fill", tint: .indigo
            )
            MetricCard(
                title: "Calories",
                value: store.metrics.calories > 0 ? "\(Int(store.metrics.calories)) kcal" : "—",
                icon: "flame.fill", tint: .orange
            )
            MetricCard(
                title: "HRV",
                value: store.metrics.hrv > 0 ? "\(Int(store.metrics.hrv)) ms" : "—",
                icon: "waveform.path.ecg", tint: .teal
            )
            MetricCard(
                title: "Workouts this week", value: "\(store.thisWeekCount())",
                icon: "dumbbell.fill", tint: .green
            )
        }
    }

    private var stepsChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Steps").font(.headline)
            Chart {
                ForEach(Array(weeklyStepsData.enumerated()), id: \.offset) { _, day in
                    BarMark(x: .value("Day", day.label), y: .value("Steps", day.steps))
                        .foregroundStyle(day.isToday ? accent : accent.opacity(0.4))
                        .cornerRadius(4)
                }
                RuleMark(y: .value("Goal", HealthStore.stepsGoal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("10k goal").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .frame(height: 160)
        }
        .sphereCard()
    }

    private struct DaySteps {
        let label: String
        let steps: Int
        let isToday: Bool
    }

    private var weeklyStepsData: [DaySteps] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EE"
        let today = Date()
        let series = store.metrics.weeklySteps.suffix(7)
        return series.enumerated().map { index, steps in
            let daysAgo = series.count - 1 - index
            let day = today.addingTimeInterval(Double(-daysAgo) * 86_400)
            return DaySteps(
                label: formatter.string(from: day),
                steps: steps,
                isToday: daysAgo == 0
            )
        }
    }

    // MARK: - Water

    private var waterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Water", systemImage: "drop.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Spacer()
                Text("\(store.waterToday) / \(HealthStore.waterGoalGlasses) glasses")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(
                value: Double(min(store.waterToday, HealthStore.waterGoalGlasses)),
                total: Double(HealthStore.waterGoalGlasses)
            )
            .tint(.blue)
            HStack {
                Button {
                    Task { try? await store.removeWaterGlass() }
                } label: {
                    Image(systemName: "minus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(store.waterToday > 0 ? .blue : .secondary)
                Spacer()
                Button {
                    Task { try? await store.addWaterGlass() }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
        .sphereCard()
    }

    // MARK: - Weight

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Weight", systemImage: "scalemass.fill")
                    .font(.headline)
                Spacer()
                Button("Log") { showingLogWeight = true }
                    .font(.subheadline.weight(.semibold))
            }
            HStack(alignment: .lastTextBaseline, spacing: 16) {
                if let latest = store.latestWeight {
                    Text(String(format: "%.1f kg", latest.kg))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    if let heightCm, let bmi = store.bmi(heightCm: heightCm) {
                        Text(String(format: "BMI %.1f", bmi))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No entries yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sphereCard()
    }

    // MARK: - Workouts

    private var workoutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Workouts").font(.title3.weight(.semibold))
                Spacer()
                Button {
                    showingAddWorkout = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            if store.workouts.isEmpty {
                Text("No workouts logged — tell your agent or tap +.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(store.sortedWorkouts.prefix(10)) { workout in
                HStack(spacing: 12) {
                    Text(workout.type.emoji)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.type.label).font(.body.weight(.medium))
                        Text(workout.date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(workout.durationMinutes) min")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                }
                .sphereCard()
            }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }
}

struct LogWeightSheet: View {
    let onLog: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kgText = ""

    private var kg: Double? {
        Double(kgText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Weight, kg", text: $kgText)
            }
            .navigationTitle("Log Weight")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let kg {
                            onLog(kg)
                        }
                        dismiss()
                    }
                    .disabled(kg.map { !(20...400).contains($0) } ?? true)
                }
            }
        }
    }
}

struct AddWorkoutSheet: View {
    let onAdd: (Workout) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var type = WorkoutType.running
    @State private var minutes = 30

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $type) {
                    ForEach(WorkoutType.allCases, id: \.self) { type in
                        Text("\(type.emoji) \(type.label)").tag(type)
                    }
                }
                Stepper("Duration: \(minutes) min", value: $minutes, in: 5...240, step: 5)
            }
            .navigationTitle("Add Workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(Workout(
                            id: Workout.newID(),
                            type: type,
                            durationMinutes: minutes,
                            date: Date()
                        ))
                        dismiss()
                    }
                }
            }
        }
    }
}

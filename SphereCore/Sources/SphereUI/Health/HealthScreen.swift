import SwiftUI
import Charts
import SphereCore

public struct HealthScreen: View {
    private let store: HealthStore
    /// From the user profile; drives the BMI card.
    private let heightCm: Double?
    /// Period tracking shows only when the profile gender is female.
    private let showsCycle: Bool
    @State private var showingLogWeight = false
    @State private var showingLogPeriod = false

    private let accent = SphereTheme.accent(for: .health)

    public init(store: HealthStore, heightCm: Double? = nil, showsCycle: Bool = false) {
        self.store = store
        self.heightCm = heightCm
        self.showsCycle = showsCycle
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                metricsGrid
                if showsCycle {
                    cycleCard
                }
                stepsChartCard
                waterCard
                energyMealCard
                weightCard
                moreSection
            }
            .padding()
        }
        .navigationTitle("Health")
        .sheet(isPresented: $showingLogPeriod) {
            LogPeriodSheet { start, flow, symptoms in
                Task { try? await store.logPeriod(start: start, flow: flow, symptoms: symptoms) }
            }
        }
        .sheet(isPresented: $showingLogWeight) {
            LogWeightSheet { kg in
                Task { try? await store.logWeight(kg: kg) }
            }
        }
        .task {
            try? await store.load()
            await store.refreshMetrics()
            if showsCycle {
                await store.importCycleFromHealth()
            }
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
                HStack(spacing: 4) {
                    Text("\(store.waterToday)")
                        .contentTransition(.numericText())
                        .sphereAnimation(SphereMotion.snappy, value: store.waterToday)
                    Text("/ \(HealthStore.waterGoalGlasses) glasses")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            ProgressView(
                value: Double(min(store.waterToday, HealthStore.waterGoalGlasses)),
                total: Double(HealthStore.waterGoalGlasses)
            )
            .tint(.blue)
            .sphereAnimation(SphereMotion.gentle, value: store.waterToday)
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
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .symbolEffect(.bounce, value: store.waterToday)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
        .sphereCard()
        .sphereHaptic(.success, trigger: store.waterToday)
    }

    // MARK: - Energy & meal (one-tap)

    private var energyMealCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            RatingSelector(
                title: "Energy today", systemImage: "bolt.fill",
                selection: store.todayEnergy(), tint: .yellow
            ) { level in
                Task { try? await store.logEnergy(level) }
            }
            RatingSelector(
                title: "Meal quality", systemImage: "fork.knife",
                selection: store.todayMeal(), tint: .green
            ) { quality in
                Task { try? await store.logMeal(quality) }
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

    // MARK: - More (secondary lists → drill-downs)

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("More").font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                MoreLink(
                    "Medications", systemImage: "pills.fill",
                    count: store.medications.isEmpty ? nil : store.medications.count
                ) { medicationsList }
                Divider().padding(.leading, 38)
                MoreLink(
                    "Lab results", systemImage: "cross.case.fill",
                    count: store.labResults.isEmpty ? nil : store.labResults.count
                ) { labResultsList }
                Divider().padding(.leading, 38)
                MoreLink(
                    "Workouts", systemImage: "figure.run",
                    count: store.workouts.isEmpty ? nil : store.workouts.count
                ) { workoutsList }
            }
            .sphereCard()
        }
    }

    private var medicationsList: some View {
        CRUDListScreen(
            title: "Medications",
            items: store.medications,
            emptyTitle: "No medications",
            emptySystemImage: "pills",
            addSheet: {
                AddMedicationSheet { medication in
                    Task { try? await store.addMedication(medication) }
                }
            },
            row: { medication in medicationRow(medication) },
            onDelete: { medication in
                Task { try? await store.removeMedication(id: medication.id) }
            },
            onRestore: { medication in
                Task { try? await store.addMedication(medication) }
            }
        )
    }

    private func medicationRow(_ medication: Medication) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { try? await store.toggleMedication(id: medication.id) }
            } label: {
                Image(systemName: medication.takenToday() ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(medication.takenToday() ? .green : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(medication.name).font(.body.weight(.medium))
                Text([medication.dosage, medication.frequency.label]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var labResultsList: some View {
        CRUDListScreen(
            title: "Lab Results",
            items: store.labResults,
            emptyTitle: "No lab results",
            emptySystemImage: "cross.case",
            addSheet: {
                AddLabResultSheet { result in
                    Task { try? await store.addLabResult(result) }
                }
            },
            row: { result in labRow(result) },
            onDelete: { result in
                Task { try? await store.removeLabResult(id: result.id) }
            },
            onRestore: { result in
                Task { try? await store.addLabResult(result) }
            }
        )
    }

    private func labRow(_ result: LabResult) -> some View {
        HStack(spacing: 12) {
            Circle().fill(result.isNormal ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name).font(.body.weight(.medium))
                if !result.refRange.isEmpty {
                    Text("ref \(result.refRange)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(result.value) \(result.unit)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(result.isNormal ? Color.primary : Color.orange)
                Text(result.date, style: .date).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var workoutsList: some View {
        CRUDListScreen(
            title: "Workouts",
            items: store.sortedWorkouts,
            emptyTitle: "No workouts logged",
            emptySystemImage: "figure.run",
            addSheet: {
                AddWorkoutSheet { workout in
                    Task { try? await store.addWorkout(workout) }
                }
            },
            row: { workout in workoutRow(workout) },
            onDelete: { workout in
                Task { try? await store.removeWorkout(id: workout.id) }
            },
            onRestore: { workout in
                Task { try? await store.addWorkout(workout) }
            }
        )
    }

    private func workoutRow(_ workout: Workout) -> some View {
        HStack(spacing: 12) {
            Text(workout.type.emoji)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.type.label).font(.body.weight(.medium))
                Text(workout.date, style: .date).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(workout.durationMinutes) min")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
        }
    }

    // MARK: - Cycle

    private var cycleTint: Color { Color(hex: 0xEC4899) }

    private var cycleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Cycle", systemImage: "circle.circle")
                    .font(.headline)
                    .foregroundStyle(cycleTint)
                Spacer()
                Button("Log period") { showingLogPeriod = true }
                    .font(.subheadline.weight(.semibold))
            }

            if let prediction = store.cyclePrediction() {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Day \(prediction.currentCycleDay)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("\(prediction.phase.emoji) \(prediction.phase.label)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(cycleTint)
                    Spacer()
                }

                ProgressView(
                    value: Double(min(prediction.currentCycleDay, prediction.averageCycleLength)),
                    total: Double(prediction.averageCycleLength)
                )
                .tint(cycleTint)

                VStack(alignment: .leading, spacing: 4) {
                    cycleRow(
                        icon: "calendar",
                        text: nextPeriodText(prediction)
                    )
                    cycleRow(
                        icon: "sparkles",
                        text: "Fertile window "
                            + "\(prediction.fertileWindow.lowerBound.formatted(.dateTime.month().day()))"
                            + "–\(prediction.fertileWindow.upperBound.formatted(.dateTime.month().day()))"
                            + " · ovulation ~\(prediction.ovulationDate.formatted(.dateTime.month().day()))"
                    )
                    if prediction.isEstimate {
                        cycleRow(
                            icon: "info.circle",
                            text: "Estimate — log a couple more periods for accuracy."
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Log your first period to see cycle day, next-period and "
                    + "fertile-window predictions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !store.sortedCycleEntries.isEmpty {
                Divider()
                ForEach(store.sortedCycleEntries.prefix(4)) { entry in
                    HStack(spacing: 10) {
                        Text(entry.flow.emoji)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.startDate, format: .dateTime.month().day().year())
                                .font(.subheadline.weight(.medium))
                            if !entry.symptoms.isEmpty {
                                Text(entry.symptoms
                                    .compactMap { CycleSymptom(rawValue: $0)?.label }
                                    .joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task { try? await store.removeCycleEntry(id: entry.id) }
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sphereCard()
    }

    private func cycleRow(icon: String, text: String) -> some View {
        Label(text, systemImage: icon).labelStyle(.titleAndIcon)
    }

    private func nextPeriodText(_ p: CyclePrediction) -> String {
        if p.isOnPeriod { return "On your period now" }
        switch p.daysUntilNextPeriod {
        case ..<0: return "Period \(-p.daysUntilNextPeriod) day(s) late"
        case 0: return "Period expected today"
        default:
            return "Next period in \(p.daysUntilNextPeriod) day(s) · "
                + p.nextPeriodStart.formatted(.dateTime.month().day())
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

struct AddMedicationSheet: View {
    let onAdd: (Medication) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var dosage = ""
    @State private var frequency = MedFrequency.once

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Dosage (e.g. 50 mcg)", text: $dosage)
                Picker("Frequency", selection: $frequency) {
                    ForEach(MedFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.label).tag(frequency)
                    }
                }
            }
            .navigationTitle("Add Medication")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(Medication(
                            id: Medication.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            dosage: dosage.trimmingCharacters(in: .whitespaces),
                            frequency: frequency
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddLabResultSheet: View {
    let onAdd: (LabResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var value = ""
    @State private var unit = ""
    @State private var refRange = ""
    @State private var isNormal = true
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Test name", text: $name)
                TextField("Value", text: $value)
                TextField("Unit (e.g. mg/dL)", text: $unit)
                TextField("Reference range", text: $refRange)
                Toggle("Within normal range", isOn: $isNormal)
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("Add Lab Result")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(LabResult(
                            id: LabResult.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            value: value.trimmingCharacters(in: .whitespaces),
                            unit: unit.trimmingCharacters(in: .whitespaces),
                            refRange: refRange.trimmingCharacters(in: .whitespaces),
                            date: date,
                            isNormal: isNormal
                        ))
                        dismiss()
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespaces).isEmpty
                            || value.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                }
            }
        }
    }
}

struct LogPeriodSheet: View {
    let onLog: (Date, FlowLevel, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startDate = Date()
    @State private var flow = FlowLevel.medium
    @State private var symptoms: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    Picker("Flow", selection: $flow) {
                        ForEach(FlowLevel.allCases, id: \.self) { level in
                            Text("\(level.emoji) \(level.label)").tag(level)
                        }
                    }
                }
                Section("Symptoms") {
                    ForEach(CycleSymptom.allCases, id: \.self) { symptom in
                        Button {
                            if symptoms.contains(symptom.rawValue) {
                                symptoms.remove(symptom.rawValue)
                            } else {
                                symptoms.insert(symptom.rawValue)
                            }
                        } label: {
                            HStack {
                                Text(symptom.label).foregroundStyle(.primary)
                                Spacer()
                                if symptoms.contains(symptom.rawValue) {
                                    Image(systemName: "checkmark").foregroundStyle(.pink)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Log Period")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onLog(startDate, flow, CycleSymptom.allCases
                            .map(\.rawValue).filter(symptoms.contains))
                        dismiss()
                    }
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

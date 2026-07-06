import SwiftUI
import SphereCore

// MARK: - List

public struct ExperimentsScreen: View {
    private let store: ExperimentStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingAdd = false

    public init(store: ExperimentStore) { self.store = store }

    public var body: some View {
        NavigationStack {
            Group {
                if store.experiments.isEmpty {
                    emptyState
                } else {
                    List {
                        if !store.running.isEmpty {
                            Section("Running") {
                                ForEach(store.running) { row($0) }
                            }
                        }
                        let past = store.experiments.filter { $0.status != .running }
                        if !past.isEmpty {
                            Section("Past") {
                                ForEach(past) { row($0) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Experiments")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New experiment")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddExperimentSheet(store: store)
            }
        }
    }

    private func row(_ experiment: Experiment) -> some View {
        NavigationLink {
            ExperimentDetailView(store: store, experiment: experiment)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(experiment.title).font(.body.weight(.medium))
                if experiment.status == .running {
                    Text("Day \(experiment.dayNumber()) of \(experiment.durationDays)")
                        .font(.caption).foregroundStyle(SphereTheme.accent(for: .health))
                } else if let headline = store.headline(for: experiment) {
                    Text(headline).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(experiment.status == .completed ? "Completed" : "Stopped")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "flask")
                .font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Run a personal experiment")
                .font(.headline)
            Text("Change one thing — caffeine, a bedtime, a habit — and Sphere measures the effect on your sleep, mood, spending and more.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Start one") { showingAdd = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}

// MARK: - Detail

struct ExperimentDetailView: View {
    let store: ExperimentStore
    let experiment: Experiment
    @Environment(\.dismiss) private var dismiss

    private var effects: [MetricEffect] { store.analysis(for: experiment) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                windowCard
                if let headline = store.headline(for: experiment) {
                    Text(headline)
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .sphereCard()
                }
                resultsCard
                if experiment.status == .running {
                    actions
                }
            }
            .padding()
        }
        .navigationTitle("What changed")
        .navigationBarTitleDisplayModeInline()
    }

    private var windowCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(experiment.title).font(.headline)
            if !experiment.note.isEmpty {
                Text(experiment.note).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(experiment.status == .running
                 ? "Day \(experiment.dayNumber()) of \(experiment.durationDays) · \(experiment.daysRemaining()) to go"
                 : "\(experiment.durationDays)-day experiment")
                .font(.caption)
                .foregroundStyle(SphereTheme.accent(for: .health))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Measured effect", systemImage: "chart.xyaxis.line")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SphereTheme.accent(for: .mindfulness))
            if effects.isEmpty {
                Text("Keep logging — an effect appears once there are at least 3 days of data before and during the change.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(effects, id: \.metricID) { effect in
                    effectRow(effect)
                }
                Text("Before vs during · a pattern, not proof.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    private func effectRow(_ effect: MetricEffect) -> some View {
        HStack {
            Text(effect.displayName).font(.subheadline)
            Spacer()
            Text(String(format: "%.1f → %.1f", effect.baselineMean, effect.duringMean))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if let pct = effect.percentChange, abs(pct) >= 1 {
                Text("\(pct > 0 ? "+" : "")\(Int(pct.rounded()))%")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(pct > 0 ? Color.green : Color.red)
                    .frame(width: 54, alignment: .trailing)
            } else {
                Text("flat").font(.caption).foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    try? await store.setStatus(experiment, .completed)
                    dismiss()
                }
            } label: {
                Label("Mark done", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                Task {
                    try? await store.setStatus(experiment, .abandoned)
                    dismiss()
                }
            } label: {
                Label("Stop early", systemImage: "stop.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Add

struct AddExperimentSheet: View {
    let store: ExperimentStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var note = ""
    @State private var duration = 14

    private let durationOptions = [7, 14, 21, 30]

    var body: some View {
        NavigationStack {
            Form {
                Section("The change") {
                    TextField("e.g. No caffeine after 2pm", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Why, or how (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section("Run for") {
                    Picker("Duration", selection: $duration) {
                        ForEach(durationOptions, id: \.self) { Text("\($0) days").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Text("Sphere compares your metrics during these \(duration) days against the \(duration) days just before.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New experiment")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            _ = try? await store.start(title: trimmed, durationDays: duration, note: note)
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

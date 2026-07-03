import SwiftUI
import Charts
import SphereCore

public struct MindfulnessScreen: View {
    private let store: MindfulnessStore
    @State private var showingLogMeditation = false
    @State private var showingAddJournal = false
    @State private var showingBreathing = false

    private let accent = SphereTheme.accent(for: .mindfulness)

    public init(store: MindfulnessStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                moodCard
                meditationCard
                breathingCard
                stressCard
                journalSection
            }
            .padding()
        }
        .navigationTitle("Mindfulness")
        .sheet(isPresented: $showingLogMeditation) {
            LogMeditationSheet { session in
                Task { try? await store.add(session) }
            }
        }
        .sheet(isPresented: $showingAddJournal) {
            AddJournalSheet { text in
                Task { try? await store.addJournal(text) }
            }
        }
        .sheet(isPresented: $showingBreathing) {
            BreathingExerciseView(accent: accent) { minutes in
                Task {
                    try? await store.add(MeditationSession(
                        id: MeditationSession.newID(),
                        type: .breathing,
                        durationMinutes: max(minutes, 1),
                        date: Date()
                    ))
                }
            }
        }
        .task {
            try? await store.load()
        }
    }

    // MARK: - Mood

    private var moodCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How are you today?").font(.headline)
            HStack(spacing: 14) {
                ForEach(1...5, id: \.self) { score in
                    Button {
                        Task { try? await store.setMood(score) }
                    } label: {
                        Text(moodEmoji(score))
                            .font(.system(size: 30))
                            .opacity(store.todaysMood() == nil || store.todaysMood() == score ? 1 : 0.35)
                            .scaleEffect(store.todaysMood() == score ? 1.2 : 1)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            HStack(spacing: 4) {
                ForEach(Array(store.last7Moods().enumerated()), id: \.offset) { _, mood in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(mood.map { moodColor($0) } ?? Color.secondary.opacity(0.15))
                        .frame(height: 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    private func moodEmoji(_ score: Int) -> String {
        ["😞", "😕", "😐", "🙂", "😄"][score - 1]
    }

    private func moodColor(_ score: Int) -> Color {
        score >= 4 ? .green : score == 3 ? .yellow : .orange
    }

    // MARK: - Meditation

    private var meditationCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Meditation").font(.headline)
                Text("\(store.currentStreak())-day streak · \(store.totalMinutes) min total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Log") { showingLogMeditation = true }
                .font(.subheadline.weight(.semibold))
        }
        .sphereCard()
    }

    private var breathingCard: some View {
        Button {
            showingBreathing = true
        } label: {
            HStack {
                Text("🌬️").font(.system(size: 30))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Breathing Exercise").font(.body.weight(.medium))
                    Text("4-7-8 · one minute to calm down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .sphereCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stress

    private var stressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stress").font(.headline)
                Spacer()
                if let today = store.todayStress() {
                    Text("\(today)/10")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(today > 6 ? .red : .secondary)
                }
            }
            Chart {
                ForEach(Array(store.last7Stress().enumerated()), id: \.offset) { index, level in
                    BarMark(x: .value("Day", index), y: .value("Stress", level))
                        .foregroundStyle(level > 6 ? Color.red : accent)
                        .cornerRadius(3)
                }
            }
            .chartXAxis(.hidden)
            .chartYScale(domain: 0...10)
            .frame(height: 70)
            HStack {
                ForEach(1...10, id: \.self) { level in
                    Button("\(level)") {
                        Task { try? await store.setStress(level) }
                    }
                    .font(.caption2.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                }
            }
        }
        .sphereCard()
    }

    // MARK: - Journal

    private var journalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Journal").font(.title3.weight(.semibold))
                Spacer()
                Button {
                    showingAddJournal = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            if store.recentJournal.isEmpty {
                Text("Write down one insight from today.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(store.recentJournal) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.text).font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .sphereCard()
            }
        }
    }
}

// MARK: - Sheets

struct LogMeditationSheet: View {
    let onLog: (MeditationSession) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 10
    @State private var type = MeditationType.breathing

    var body: some View {
        NavigationStack {
            Form {
                Stepper("\(minutes) minutes", value: $minutes, in: 1...240, step: 5)
                Picker("Type", selection: $type) {
                    ForEach(MeditationType.allCases, id: \.self) { type in
                        Text("\(type.emoji) \(type.label)").tag(type)
                    }
                }
            }
            .navigationTitle("Log Meditation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onLog(MeditationSession(
                            id: MeditationSession.newID(),
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

struct AddJournalSheet: View {
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("What's on your mind?", text: $text, axis: .vertical)
                    .lineLimit(5...12)
            }
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onAdd(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

/// 4-7-8 breathing with an animated circle. On dismiss, elapsed whole
/// minutes are logged as a breathing meditation session.
struct BreathingExerciseView: View {
    let accent: Color
    let onFinish: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.inhale
    @State private var startedAt = Date()

    enum Phase: CaseIterable {
        case inhale, hold, exhale

        var label: String {
            switch self {
            case .inhale: "Breathe in"
            case .hold: "Hold"
            case .exhale: "Breathe out"
            }
        }

        var seconds: Double {
            switch self {
            case .inhale: 4
            case .hold: 7
            case .exhale: 8
            }
        }

        var scale: CGFloat {
            switch self {
            case .inhale, .hold: 1.0
            case .exhale: 0.45
            }
        }
    }

    var body: some View {
        VStack(spacing: 40) {
            Text(phase.label)
                .font(.title2.weight(.semibold))
                .contentTransition(.opacity)
            Circle()
                .fill(accent.opacity(0.25))
                .overlay(Circle().stroke(accent, lineWidth: 3))
                .frame(width: 220, height: 220)
                .scaleEffect(phase.scale)
                .animation(.easeInOut(duration: phase.seconds), value: phase)
            Button("Done") {
                onFinish(Int(Date().timeIntervalSince(startedAt) / 60))
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
        .padding(40)
        .task {
            startedAt = Date()
            while !Task.isCancelled {
                for next in Phase.allCases {
                    phase = next
                    try? await Task.sleep(for: .seconds(next.seconds))
                    if Task.isCancelled { return }
                }
            }
        }
    }
}

import SwiftUI
import Charts
import SphereCore

public struct MindfulnessScreen: View {
    private let store: MindfulnessStore
    @State private var showingLogMeditation = false
    @State private var showingAddJournal = false
    @State private var showingBreathing = false
    @State private var showingFocus = false
    @State private var breathingPattern = BreathingPattern.fourSevenEight
    @State private var gratitudeDraft = ""

    private let accent = SphereTheme.accent(for: .mindfulness)

    public init(store: MindfulnessStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                affirmationCard
                focusCard
                moodCard
                gratitudeCard
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
            BreathingExerciseView(accent: accent, pattern: breathingPattern) { minutes in
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
        .sheet(isPresented: $showingFocus) {
            FocusTimerSheet(accent: accent) { minutes in
                Task { try? await store.logFocusSession(minutes: minutes) }
            }
        }
        .task {
            try? await store.load()
        }
    }

    // MARK: - Focus & discipline (Tysh-inspired)

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Focus", systemImage: "scope").font(.headline).foregroundStyle(accent)
                Spacer()
                Text("Discipline \(store.disciplineScore())/100")
                    .font(.subheadline.weight(.semibold))
            }
            ProgressView(value: Double(store.disciplineScore()), total: 100).tint(accent)
            HStack(spacing: 16) {
                stat("\(store.focusMinutesToday())m", "focused today")
                stat("\(store.focusStreak())d", "streak")
            }
            Button {
                showingFocus = true
            } label: {
                Label("Start a focus session", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
        .sphereCard()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.weight(.bold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Affirmation

    private var affirmationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Today's affirmation", systemImage: "quote.opening")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(accent)
            Text(store.dailyAffirmation())
                .font(.title3.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    // MARK: - Gratitude

    private var gratitudeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Gratitude", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(.pink)
            HStack(spacing: 8) {
                TextField("One thing you're grateful for", text: $gratitudeDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addGratitude)
                Button(action: addGratitude) {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.pink)
                .disabled(gratitudeDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(store.gratitude.prefix(3)) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundStyle(.pink)
                    Text(entry.content).font(.subheadline)
                    Spacer()
                }
            }
        }
        .sphereCard()
    }

    private func addGratitude() {
        let text = gratitudeDraft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        gratitudeDraft = ""
        Task { try? await store.addGratitude(text) }
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
        Menu {
            ForEach(BreathingPattern.allCases) { pattern in
                Button {
                    breathingPattern = pattern
                    showingBreathing = true
                } label: {
                    Text("\(pattern.label) · \(pattern.subtitle)")
                }
            }
        } label: {
            HStack {
                Text("🌬️").font(.system(size: 30))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Breathing Exercise").font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text("Pick a pattern — 4-7-8, box, or coherent")
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

/// Guided breathing with an animated circle, driven by the chosen pattern.
/// On dismiss, elapsed whole minutes are logged as a breathing session.
struct BreathingExerciseView: View {
    let accent: Color
    let pattern: BreathingPattern
    let onFinish: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label = "Breathe in"
    @State private var scale: CGFloat = 1.0
    @State private var animationDuration: Double = 4
    @State private var startedAt = Date()

    private var phases: [(label: String, seconds: Double, scale: CGFloat)] {
        let timing = pattern.timing
        var result: [(String, Double, CGFloat)] = []
        if timing.inhale > 0 { result.append(("Breathe in", Double(timing.inhale), 1.0)) }
        if timing.holdIn > 0 { result.append(("Hold", Double(timing.holdIn), 1.0)) }
        if timing.exhale > 0 { result.append(("Breathe out", Double(timing.exhale), 0.45)) }
        if timing.holdOut > 0 { result.append(("Hold", Double(timing.holdOut), 0.45)) }
        return result.map { (label: $0.0, seconds: $0.1, scale: $0.2) }
    }

    var body: some View {
        VStack(spacing: 40) {
            Text(pattern.label).font(.headline).foregroundStyle(.secondary)
            Text(label)
                .font(.title2.weight(.semibold))
                .contentTransition(.opacity)
            Circle()
                .fill(accent.opacity(0.25))
                .overlay(Circle().stroke(accent, lineWidth: 3))
                .frame(width: 220, height: 220)
                .scaleEffect(scale)
                .animation(.easeInOut(duration: animationDuration), value: scale)
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
                for phase in phases {
                    label = phase.label
                    animationDuration = phase.seconds
                    scale = phase.scale
                    try? await Task.sleep(for: .seconds(phase.seconds))
                    if Task.isCancelled { return }
                }
            }
        }
    }
}

/// A distraction-free focus timer (Tysh-style). Pick a length, run a
/// countdown, and the elapsed minutes log as a focus session.
struct FocusTimerSheet: View {
    let accent: Color
    let onFinish: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var totalMinutes = 25
    @State private var remaining = 0
    @State private var running = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                if running {
                    Text(timeString(remaining))
                        .font(.system(size: 60, weight: .bold, design: .monospaced))
                    Text("Stay with one thing.").foregroundStyle(.secondary)
                    Button("Finish now") { finish() }
                        .buttonStyle(.bordered).tint(accent)
                } else {
                    Image(systemName: "scope").font(.system(size: 44)).foregroundStyle(accent)
                    Stepper("Focus for \(totalMinutes) min", value: $totalMinutes, in: 5...120, step: 5)
                        .padding(.horizontal, 40)
                    Button("Start") { start() }
                        .buttonStyle(.borderedProminent).tint(accent)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Focus session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task(id: running) {
                guard running else { return }
                while running, remaining > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    if !running { return }
                    remaining -= 1
                }
                if running, remaining <= 0 { finish() }
            }
        }
    }

    private func start() {
        remaining = totalMinutes * 60
        running = true
    }

    private func finish() {
        let elapsed = max((totalMinutes * 60 - remaining) / 60, 1)
        running = false
        onFinish(elapsed)
        dismiss()
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

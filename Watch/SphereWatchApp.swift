import SwiftUI
import WatchKit
import SphereCore

@main
struct SphereWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model)
        }
    }
}

private let accent = Color(red: 10 / 255, green: 132 / 255, blue: 1)

/// Local, optimistic UI state layered on top of the phone-owned snapshot.
/// None of this is persisted — the snapshot remains the single source of
/// truth and clears these overlays the moment a fresh one arrives.
@MainActor
@Observable
private final class QuickLogOverlay {
    /// Added to `snapshot.waterToday` until the next snapshot arrives.
    var waterDelta = 0
    /// Mood tapped locally, shown highlighted until the next snapshot arrives.
    var optimisticMood: Int?
    /// Meditation logged locally this session (snapshot may lag behind).
    var optimisticMeditated = false
    /// "Will sync when your iPhone is nearby." — cleared after a few seconds
    /// or when a fresh snapshot arrives.
    var offlineHint = false
    private var hintTask: Task<Void, Never>?

    func reset() {
        waterDelta = 0
        optimisticMood = nil
        optimisticMeditated = false
        offlineHint = false
        hintTask?.cancel()
    }

    func showOfflineHint() {
        offlineHint = true
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.offlineHint = false
        }
    }
}

/// Local state for the ask-agent flow: pending/waiting/offline messaging
/// that the snapshot alone can't express (it only knows the last reply).
@MainActor
@Observable
private final class AskAgentState {
    enum Phase {
        case idle
        case thinking
        case stillWaiting
        case queuedOffline
    }

    private(set) var phase: Phase = .idle
    private var submittedAt: Date?
    private var waitTask: Task<Void, Never>?

    func submitted(reachable: Bool) {
        submittedAt = Date()
        waitTask?.cancel()
        if !reachable {
            phase = .queuedOffline
            return
        }
        phase = .thinking
        waitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.phase = .stillWaiting
        }
    }

    /// Called whenever a snapshot arrives; clears pending state once the
    /// reply is newer than the submission that triggered it.
    func receivedSnapshot(agentReplyAt: Date?) {
        guard let submittedAt else { return }
        if let agentReplyAt, agentReplyAt >= submittedAt {
            waitTask?.cancel()
            waitTask = nil
            self.submittedAt = nil
            phase = .idle
            WKInterfaceDevice.current().play(.success)
        }
    }
}

struct WatchRootView: View {
    let model: WatchModel
    @State private var overlay = QuickLogOverlay()
    @State private var askState = AskAgentState()

    private var snapshot: WidgetSnapshot { model.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.3), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: Double(snapshot.lifeScore) / 100)
                        .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(snapshot.lifeScore)").font(.title2.weight(.bold))
                        Text("Life").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 90, height: 90)

                HStack(spacing: 10) {
                    Label(snapshot.bestName, systemImage: "arrow.up")
                        .foregroundStyle(.green)
                    Label(snapshot.needsFocusName, systemImage: "arrow.down")
                        .foregroundStyle(.orange)
                }
                .font(.caption2)

                if !snapshot.topFocus.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Today's Focus")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(snapshot.topFocus.prefix(3).enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 6) {
                                Text(item.emoji)
                                Text(item.title).font(.caption2).lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                quickLog

                if !snapshot.shopping.isEmpty {
                    shoppingList
                }

                askAgent

                staleness
            }
            .padding()
        }
        .onChange(of: snapshot) { _, new in
            overlay.reset()
            askState.receivedSnapshot(agentReplyAt: new.agentReplyAt)
        }
    }

    private var shoppingList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shopping")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(snapshot.shopping) { item in
                Button {
                    sendCommand(.checkShopping(id: item.id))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                        Text(item.title).font(.caption2).lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var askAgent: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextFieldLink(prompt: Text("Tell or ask your agent")) {
                Label("Ask", systemImage: "mic.fill")
            } onSubmit: { text in
                let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return }
                let reachable = sendCommand(.capture(text: query))
                askState.submitted(reachable: reachable)
            }
            .font(.caption2)
            .tint(accent)

            switch askState.phase {
            case .idle:
                if !snapshot.captureResults.isEmpty {
                    captureChips
                } else if let reply = snapshot.agentReply, !reply.isEmpty {
                    Text(reply)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let at = snapshot.agentReplyAt,
                   !snapshot.captureResults.isEmpty || !(snapshot.agentReply ?? "").isEmpty {
                    TimelineView(.periodic(from: at, by: 60)) { context in
                        Text(RelativeTimeFormat.short(from: at, to: context.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            case .thinking:
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Thinking…").font(.caption2).foregroundStyle(.secondary)
                }
            case .stillWaiting:
                Text("Still waiting for your iPhone…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .queuedOffline:
                Text("Will ask when your iPhone is nearby.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var captureChips: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(snapshot.captureResults.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: line.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(line.isError ? Color.orange : Color.green)
                    Text(line.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Log")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    overlay.waterDelta += 1
                    sendCommand(.logWater)
                } label: {
                    Label(waterProgressLabel, systemImage: "drop.fill")
                }
                .tint(.blue)

                Button {
                    WKInterfaceDevice.current().play(.click)
                    overlay.optimisticMeditated = true
                    sendCommand(.logMeditation(minutes: 10))
                } label: {
                    Label("10 min", systemImage: meditationDone ? "checkmark.circle.fill" : "figure.mind.and.body")
                }
                .tint(meditationDone ? .green : accent)
            }
            .font(.caption2)

            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { score in
                    Button("\(moodEmoji(score))") {
                        WKInterfaceDevice.current().play(.click)
                        overlay.optimisticMood = score
                        sendCommand(.logMood(score))
                    }
                    .buttonStyle(.plain)
                    .font(.title3)
                    .opacity(highlightedMood == score ? 1.0 : 0.4)
                    .scaleEffect(highlightedMood == score ? 1.15 : 1.0)
                    .animation(.spring(response: 0.25), value: highlightedMood)
                }
            }

            if overlay.offlineHint {
                Text("Will sync when your iPhone is nearby.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var waterProgressLabel: String {
        "\(snapshot.waterToday + overlay.waterDelta) / \(snapshot.waterGoal)"
    }

    private var meditationDone: Bool {
        snapshot.meditatedToday || overlay.optimisticMeditated
    }

    private var highlightedMood: Int? {
        overlay.optimisticMood ?? snapshot.moodToday
    }

    /// A snapshot this old was never actually synced from the phone — it's
    /// the built-in placeholder (whose `updatedAt` is the Unix epoch), not a
    /// real but very stale reading. Anything genuinely stale in practice
    /// (phone unreachable for days) still deserves this treatment: showing
    /// a computed "20640d ago" is never more useful than a plain "waiting"
    /// message.
    private static let neverSyncedHorizon: TimeInterval = 7 * 24 * 60 * 60

    private var staleness: some View {
        Group {
            let age = Date().timeIntervalSince(snapshot.updatedAt)
            if age > Self.neverSyncedHorizon {
                Text("Waiting for your iPhone…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if age > 30 * 60 {
                TimelineView(.everyMinute) { context in
                    Text("Updated \(RelativeTimeFormat.short(from: snapshot.updatedAt, to: context.date)) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func moodEmoji(_ score: Int) -> String {
        ["😞", "😕", "😐", "🙂", "😄"][score - 1]
    }

    /// Sends the command and, if it couldn't go out live, shows the shared
    /// offline hint. Returns whether it went out live.
    @discardableResult
    private func sendCommand(_ command: WatchCommand) -> Bool {
        let reachable = model.send(command)
        if !reachable {
            overlay.showOfflineHint()
        }
        return reachable
    }
}

/// Minimal relative-time formatting shared by the staleness line and the
/// agent-reply timestamp — avoids pulling in `RelativeDateTimeFormatter`
/// configuration for a one-line "Xm/Xh ago" label.
enum RelativeTimeFormat {
    static func short(from date: Date, to now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}

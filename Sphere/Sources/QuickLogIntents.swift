import AppIntents
import SphereCore
import WidgetKit

/// Voice / Shortcuts entry points for the fastest logs, backed by the shared
/// App Group database (so they work from Siri and interactive widget buttons
/// without launching the app). Writes go through `QuickLogSQL`. Also compiled
/// into the widget extension target (see project.yml) so `Button(intent:)`
/// can reference these types directly.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a glass of water"
    static let description = IntentDescription("Records one glass of water in Sphere.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let writer = SharedDatabaseLocation.openWriter() else {
            return .result(dialog: "Open Sphere once first, then try again.")
        }
        let total = try await QuickLogSQL.incrementWater(writer)
        WidgetSnapshotPatch.applyWaterToday(total)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Logged. That's \(total) glass\(total == 1 ? "" : "es") today.")
    }
}

struct LogMoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log my mood"
    static let description = IntentDescription("Records today's mood in Sphere on a 1–5 scale.")

    @Parameter(title: "Mood", inclusiveRange: (1, 5))
    var score: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let writer = SharedDatabaseLocation.openWriter() else {
            return .result(dialog: "Open Sphere once first, then try again.")
        }
        try await QuickLogSQL.setMood(writer, score: score)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Logged your mood as \(score) out of 5.")
    }
}

struct LogMeditationIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a meditation"
    static let description = IntentDescription("Records a meditation session in Sphere.")

    @Parameter(title: "Minutes", default: 10, inclusiveRange: (1, 240))
    var minutes: Int

    init() {}

    init(minutes: Int) {
        self.minutes = minutes
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let writer = SharedDatabaseLocation.openWriter() else {
            return .result(dialog: "Open Sphere once first, then try again.")
        }
        try await QuickLogSQL.addMeditation(writer, minutes: minutes)
        WidgetSnapshotPatch.applyMeditatedToday()
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Logged a \(minutes)-minute meditation.")
    }
}

/// Patches the persisted `WidgetSnapshot` right after an intent writes to the
/// shared DB, so a widget-button tap reflects instantly — the app isn't
/// running to rebuild the snapshot itself. The app's next `refreshWidget()`
/// overwrites this with the authoritative recomputed snapshot; that's fine,
/// this is just a same-second visual patch. All fields are `let`, so each
/// patch reads the current snapshot and rebuilds it rather than mutating.
private enum WidgetSnapshotPatch {
    @MainActor
    static func applyWaterToday(_ total: Int) {
        guard let store = WidgetSnapshotStore.shared() else { return }
        let current = store.read() ?? .placeholder
        store.write(WidgetSnapshot(
            lifeScore: current.lifeScore,
            bestEmoji: current.bestEmoji,
            bestName: current.bestName,
            needsFocusEmoji: current.needsFocusEmoji,
            needsFocusName: current.needsFocusName,
            topFocus: current.topFocus,
            shopping: current.shopping,
            agentReply: current.agentReply,
            agentReplyAt: current.agentReplyAt,
            captureResults: current.captureResults,
            suggestions: current.suggestions,
            waterToday: total,
            waterGoal: current.waterGoal,
            meditatedToday: current.meditatedToday,
            moodToday: current.moodToday,
            updatedAt: Date()
        ))
    }

    @MainActor
    static func applyMeditatedToday() {
        guard let store = WidgetSnapshotStore.shared() else { return }
        let current = store.read() ?? .placeholder
        store.write(WidgetSnapshot(
            lifeScore: current.lifeScore,
            bestEmoji: current.bestEmoji,
            bestName: current.bestName,
            needsFocusEmoji: current.needsFocusEmoji,
            needsFocusName: current.needsFocusName,
            topFocus: current.topFocus,
            shopping: current.shopping,
            agentReply: current.agentReply,
            agentReplyAt: current.agentReplyAt,
            captureResults: current.captureResults,
            suggestions: current.suggestions,
            waterToday: current.waterToday,
            waterGoal: current.waterGoal,
            meditatedToday: true,
            moodToday: current.moodToday,
            updatedAt: Date()
        ))
    }
}

/// Registers Siri phrases so the intents work with "Hey Siri" and appear in
/// Shortcuts without any setup.
struct SphereShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: [
                "Log water in \(.applicationName)",
                "Log a glass of water in \(.applicationName)",
            ],
            shortTitle: "Log water",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: LogMoodIntent(),
            phrases: ["Log my mood in \(.applicationName)"],
            shortTitle: "Log mood",
            systemImageName: "face.smiling"
        )
        AppShortcut(
            intent: LogMeditationIntent(),
            phrases: ["Log a meditation in \(.applicationName)"],
            shortTitle: "Log meditation",
            systemImageName: "figure.mind.and.body"
        )
    }
}

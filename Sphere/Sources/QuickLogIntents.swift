import AppIntents
import SphereCore
import WidgetKit

/// Voice / Shortcuts entry points for the fastest logs, backed by the shared
/// App Group database (so they work from Siri and, later, interactive widget
/// buttons without launching the app). Writes go through `QuickLogSQL`.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a glass of water"
    static let description = IntentDescription("Records one glass of water in Sphere.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let writer = SharedDatabaseLocation.openWriter() else {
            return .result(dialog: "Open Sphere once first, then try again.")
        }
        let total = try await QuickLogSQL.incrementWater(writer)
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

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let writer = SharedDatabaseLocation.openWriter() else {
            return .result(dialog: "Open Sphere once first, then try again.")
        }
        try await QuickLogSQL.addMeditation(writer, minutes: minutes)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Logged a \(minutes)-minute meditation.")
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

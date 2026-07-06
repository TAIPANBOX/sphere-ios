import AppIntents

/// Registers "Log water" as a watch App Shortcut so it works with Siri on the
/// wrist and is assignable to the Ultra's Action Button via the Shortcuts app
/// (Action Button → Shortcut → "Log Water in Sphere"). It reuses
/// `LogWaterWatchIntent`, so a Siri / Action Button trigger takes the same
/// queue-and-drain path as the interactive Smart Stack widget: the intent runs
/// in the watch app process, queues the log, and `WatchModel` relays it to the
/// phone on the next reachability. Defined in the watch APP target only (an
/// AppShortcutsProvider belongs to one target).
struct WatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWaterWatchIntent(),
            phrases: [
                "Log water in \(.applicationName)",
                "Log a glass of water in \(.applicationName)",
            ],
            shortTitle: "Log water",
            systemImageName: "drop.fill"
        )
    }
}

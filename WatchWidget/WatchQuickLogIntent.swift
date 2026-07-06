import AppIntents
import SphereCore
import WidgetKit

/// Logs a glass of water from the watch — usable as an interactive Smart Stack
/// widget button and (see `WatchShortcuts`) from Siri / the Action Button.
///
/// It runs in whichever watch process invokes it. The watch WIDGET EXTENSION
/// has no WCSession and no database, so this intent cannot reach the phone
/// directly. Instead it (1) queues the command in the shared App Group via
/// `PendingWatchLogStore` and (2) optimistically patches the persisted
/// `WidgetSnapshot` (waterToday + 1) so the widget reflects the tap instantly.
/// The watch APP drains the queue on its next activation and sends the real
/// `WatchCommand`s to the phone, which owns the source of truth.
///
/// Shared into both the watch widget extension and the watch app targets (see
/// project.yml), mirroring how `QuickLogIntents.swift` is shared on iOS.
struct LogWaterWatchIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a glass of water"
    static let description = IntentDescription("Records one glass of water in Sphere.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingWatchLogStore.shared()?.enqueue(.logWater)
        if let store = WidgetSnapshotStore.shared() {
            let current = store.read() ?? .placeholder
            store.write(current.incrementingWater(by: 1))
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

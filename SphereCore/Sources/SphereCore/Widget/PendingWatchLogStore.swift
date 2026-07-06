import Foundation

/// A bounded, App-Group-backed queue of ``WatchCommand``s produced by watch
/// widget App Intents, which cannot reach the phone (no WCSession) or the
/// database themselves. The watch APP drains this on its next activation and
/// sends each command to the phone over WCSession, where it becomes real
/// persisted state.
///
/// Stored as a JSON array of ``WatchCommand`` wire dictionaries in the watch
/// App Group container, so it survives the widget-extension process ending
/// before the app runs again. The queue is bounded so a phone that stays
/// unreachable for a long time can't grow it without limit; the oldest entries
/// are dropped past the cap (the snapshot patch already gave instant feedback,
/// and water logs are low-stakes).
public struct PendingWatchLogStore: Sendable {
    /// Hard cap on queued commands; older ones are dropped past this.
    public static let maxQueued = 50

    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("pendingWatchLogs.json")
    }

    /// App-group-backed store shared by the watch app and the watch widget
    /// extension. Returns nil when the App Group is unavailable (unsigned/CI).
    public static func shared(groupID: String = WidgetSnapshotStore.appGroupID) -> PendingWatchLogStore? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)
        else { return nil }
        return PendingWatchLogStore(directory: container)
    }

    /// Appends a command to the queue (capped to the most recent `maxQueued`).
    /// A read-modify-write: fine because only the single foreground widget or
    /// app writes at a time, and losing a low-stakes water log under a rare
    /// race is acceptable.
    public func enqueue(_ command: WatchCommand) {
        var queue = read()
        queue.append(command)
        if queue.count > Self.maxQueued {
            queue.removeFirst(queue.count - Self.maxQueued)
        }
        write(queue)
    }

    /// Returns all queued commands and clears the queue in one step, so a
    /// second drain returns nothing (idempotent). The caller sends each to the
    /// phone; if a send fails it may re-enqueue.
    public func drain() -> [WatchCommand] {
        let queue = read()
        guard !queue.isEmpty else { return [] }
        clear()
        return queue
    }

    public func read() -> [WatchCommand] {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return raw.compactMap(WatchCommand.decode)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func write(_ queue: [WatchCommand]) {
        let raw = queue.map { $0.encode() }
        guard let data = try? JSONSerialization.data(withJSONObject: raw) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

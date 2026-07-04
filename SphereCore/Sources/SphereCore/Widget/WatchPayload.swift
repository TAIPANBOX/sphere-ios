import Foundation

/// Bridges a ``WidgetSnapshot`` to/from a WatchConnectivity dictionary.
/// App Group containers are per-platform, so the phone can't share its
/// snapshot file with the watch — it sends this payload over WCSession
/// instead, and the watch persists it to its own App Group for the
/// complication.
public enum WatchPayload {
    static let snapshotKey = "snapshot"

    public static func encode(_ snapshot: WidgetSnapshot) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(snapshot) else { return [:] }
        return [snapshotKey: data]
    }

    public static func decode(_ dictionary: [String: Any]) -> WidgetSnapshot? {
        guard let data = dictionary[snapshotKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

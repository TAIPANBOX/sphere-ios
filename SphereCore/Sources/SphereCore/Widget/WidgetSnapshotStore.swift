import Foundation

/// Reads/writes the ``WidgetSnapshot`` as JSON in a shared directory (the
/// App Group container in the app, a temp dir in tests). Both the app and
/// the widget extension point at the same App Group.
public struct WidgetSnapshotStore: Sendable {
    public static let appGroupID = "group.app.sphere.shared"

    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("widget-snapshot.json")
    }

    /// App-group-backed store shared by the app and the widget. Returns nil
    /// if the App Group container is unavailable (missing entitlement).
    public static func shared(groupID: String = appGroupID) -> WidgetSnapshotStore? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)
        else { return nil }
        return WidgetSnapshotStore(directory: container)
    }

    public func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

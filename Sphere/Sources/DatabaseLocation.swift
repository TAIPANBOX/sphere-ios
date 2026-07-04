import Foundation
import SphereCore

/// Resolves where the app databases live and migrates them into the App
/// Group container on first run so extensions (widget, App Intents, watch)
/// can open them too.
///
/// - Signed builds: `group.app.sphere.shared/Databases/`.
/// - Unsigned / CI builds (no App Group entitlement): the legacy Application
///   Support directory — same guarded-nil fallback the widget store uses.
///
/// The move copies the main DB plus its `-wal`/`-shm` sidecars (the correct
/// way to relocate a WAL database), verifies the copy, then deletes the old
/// files. It runs before any GRDB connection is opened, so nothing holds the
/// files.
enum DatabaseLocation {
    private static let bases = ["sphere.db", "sphere.engram.db"]
    private static let suffixes = ["", "-wal", "-shm"]

    static func resolve() -> URL {
        let fm = FileManager.default
        let legacyDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sphere", isDirectory: true)
        try? fm.createDirectory(at: legacyDir, withIntermediateDirectories: true)

        guard let group = fm.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroupID
        ) else {
            return legacyDir
        }

        let sharedDir = group.appendingPathComponent("Databases", isDirectory: true)
        try? fm.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        migrateIfNeeded(from: legacyDir, to: sharedDir, fm: fm)
        return sharedDir
    }

    private static func migrateIfNeeded(from old: URL, to new: URL, fm: FileManager) {
        for base in bases {
            let newMain = new.appendingPathComponent(base)
            let oldMain = old.appendingPathComponent(base)
            guard !fm.fileExists(atPath: newMain.path),
                  fm.fileExists(atPath: oldMain.path) else { continue }

            for suffix in suffixes {
                let src = old.appendingPathComponent(base + suffix)
                let dst = new.appendingPathComponent(base + suffix)
                if fm.fileExists(atPath: src.path) { try? fm.copyItem(at: src, to: dst) }
            }
            // Only delete the originals once the main file is confirmed moved.
            if fm.fileExists(atPath: newMain.path) {
                for suffix in suffixes {
                    try? fm.removeItem(at: old.appendingPathComponent(base + suffix))
                }
            }
        }
    }
}

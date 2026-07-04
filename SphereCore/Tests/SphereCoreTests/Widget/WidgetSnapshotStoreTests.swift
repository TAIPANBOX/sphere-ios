import Foundation
import Testing
@testable import SphereCore

@Suite("WidgetSnapshotStore")
struct WidgetSnapshotStoreTests {
    private func makeStore() -> WidgetSnapshotStore {
        WidgetSnapshotStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("widget-tests-\(UUID().uuidString)")
        )
    }

    @Test func readReturnsNilBeforeAnyWrite() {
        #expect(makeStore().read() == nil)
    }

    @Test func snapshotRoundTrips() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-rt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = WidgetSnapshotStore(directory: dir)

        let snapshot = WidgetSnapshot(
            lifeScore: 67,
            bestEmoji: "💰",
            bestName: "Finance",
            needsFocusEmoji: "🌊",
            needsFocusName: "Rest",
            topFocus: [
                .init(emoji: "🎂", title: "Olena's Birthday"),
                .init(emoji: "👟", title: "Reach your step goal"),
            ],
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        store.write(snapshot)

        let reloaded = try #require(store.read())
        #expect(reloaded == snapshot)
        #expect(reloaded.topFocus.first?.title == "Olena's Birthday")
    }

    @Test func writeOverwritesPrevious() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-ov-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = WidgetSnapshotStore(directory: dir)

        store.write(WidgetSnapshot.placeholder)
        store.write(WidgetSnapshot(
            lifeScore: 40, bestEmoji: "📚", bestName: "Learning",
            needsFocusEmoji: "💰", needsFocusName: "Finance",
            topFocus: [], updatedAt: Date(timeIntervalSince1970: 5)
        ))
        #expect(store.read()?.lifeScore == 40)
    }
}

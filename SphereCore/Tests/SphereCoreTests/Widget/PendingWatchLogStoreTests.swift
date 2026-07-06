import Foundation
import Testing
@testable import SphereCore

@Suite("PendingWatchLogStore")
struct PendingWatchLogStoreTests {
    private func makeStore() throws -> PendingWatchLogStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-logs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PendingWatchLogStore(directory: dir)
    }

    @Test func drainIsEmptyBeforeAnyEnqueue() throws {
        #expect(try makeStore().drain().isEmpty)
    }

    @Test func enqueuePreservesOrderAndRoundTripsCommands() throws {
        let store = try makeStore()
        store.enqueue(.logWater)
        store.enqueue(.logMeditation(minutes: 15))
        store.enqueue(.logWater)

        let drained = store.drain()
        #expect(drained == [.logWater, .logMeditation(minutes: 15), .logWater])
    }

    @Test func drainIsIdempotentAndClears() throws {
        let store = try makeStore()
        store.enqueue(.logWater)

        #expect(store.drain() == [.logWater])
        // Second drain returns nothing — the app won't double-send.
        #expect(store.drain().isEmpty)
        #expect(store.read().isEmpty)
    }

    @Test func queueIsBoundedToMostRecent() throws {
        let store = try makeStore()
        for _ in 0..<(PendingWatchLogStore.maxQueued + 10) {
            store.enqueue(.logWater)
        }
        #expect(store.read().count == PendingWatchLogStore.maxQueued)
    }
}

@Suite("WidgetSnapshot.incrementingWater")
struct WidgetSnapshotWaterPatchTests {
    @Test func bumpsWaterAndStampsUpdatedAt() {
        let now = Date(timeIntervalSince1970: 2_000)
        let patched = WidgetSnapshot.placeholder.incrementingWater(by: 1, asOf: now)
        #expect(patched.waterToday == WidgetSnapshot.placeholder.waterToday + 1)
        #expect(patched.updatedAt == now)
        // Everything else is preserved.
        #expect(patched.lifeScore == WidgetSnapshot.placeholder.lifeScore)
        #expect(patched.waterGoal == WidgetSnapshot.placeholder.waterGoal)
    }

    @Test func clampsAtZero() {
        let patched = WidgetSnapshot.placeholder.incrementingWater(by: -5)
        #expect(patched.waterToday == 0)
    }
}

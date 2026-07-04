import Foundation
import Testing
@testable import SphereCore

@Suite("WatchPayload")
struct WatchPayloadTests {
    @Test func snapshotRoundTripsThroughDictionary() throws {
        let snapshot = WidgetSnapshot(
            lifeScore: 58,
            bestEmoji: "🫀",
            bestName: "Health",
            needsFocusEmoji: "💰",
            needsFocusName: "Finance",
            topFocus: [.init(emoji: "🎂", title: "Olena's Birthday")],
            updatedAt: Date(timeIntervalSince1970: 42)
        )
        let payload = WatchPayload.encode(snapshot)
        #expect(payload[WatchPayload.snapshotKey] is Data)

        let decoded = try #require(WatchPayload.decode(payload))
        #expect(decoded == snapshot)
    }

    @Test func decodeRejectsUnrelatedDictionary() {
        #expect(WatchPayload.decode([:]) == nil)
        #expect(WatchPayload.decode(["other": 1]) == nil)
        #expect(WatchPayload.decode([WatchPayload.snapshotKey: "not data"]) == nil)
    }
}

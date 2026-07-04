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

    @Test func snapshotCarriesShoppingAndAgentReply() throws {
        let snapshot = WidgetSnapshot(
            lifeScore: 60, bestEmoji: "🫀", bestName: "Health",
            needsFocusEmoji: "💰", needsFocusName: "Finance", topFocus: [],
            shopping: [.init(id: "s1", title: "Milk"), .init(id: "s2", title: "Eggs")],
            agentReply: "You slept 7.5 hours.",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let decoded = try #require(WatchPayload.decode(WatchPayload.encode(snapshot)))
        #expect(decoded.shopping.map(\.title) == ["Milk", "Eggs"])
        #expect(decoded.agentReply == "You slept 7.5 hours.")
    }

    @Test func decodesLegacySnapshotWithoutNewFields() throws {
        // A snapshot written by an older build omits shopping / agentReply.
        let legacy = """
        {"lifeScore":50,"bestEmoji":"🫀","bestName":"Health","needsFocusEmoji":"💰",\
        "needsFocusName":"Finance","topFocus":[],"updatedAt":0}
        """
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(legacy.utf8))
        #expect(decoded.shopping.isEmpty)
        #expect(decoded.agentReply == nil)
        #expect(decoded.lifeScore == 50)
    }
}

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

    @Test func snapshotRoundTripsTodayStateFields() throws {
        let snapshot = WidgetSnapshot(
            lifeScore: 65, bestEmoji: "🫀", bestName: "Health",
            needsFocusEmoji: "💰", needsFocusName: "Finance", topFocus: [],
            agentReply: "You're at 5 of 8 glasses.",
            agentReplyAt: Date(timeIntervalSince1970: 100),
            waterToday: 5,
            waterGoal: 8,
            meditatedToday: true,
            moodToday: 4,
            updatedAt: Date(timeIntervalSince1970: 101)
        )
        let decoded = try #require(WatchPayload.decode(WatchPayload.encode(snapshot)))
        #expect(decoded == snapshot)
        #expect(decoded.waterToday == 5)
        #expect(decoded.waterGoal == 8)
        #expect(decoded.meditatedToday == true)
        #expect(decoded.moodToday == 4)
        #expect(decoded.agentReplyAt == Date(timeIntervalSince1970: 100))
    }

    @Test func decodesLegacySnapshotWithoutNewFields() throws {
        // A snapshot written by an older build omits shopping / agentReply /
        // the today-state fields.
        let legacy = """
        {"lifeScore":50,"bestEmoji":"🫀","bestName":"Health","needsFocusEmoji":"💰",\
        "needsFocusName":"Finance","topFocus":[],"updatedAt":0}
        """
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(legacy.utf8))
        #expect(decoded.shopping.isEmpty)
        #expect(decoded.agentReply == nil)
        #expect(decoded.agentReplyAt == nil)
        #expect(decoded.waterToday == 0)
        #expect(decoded.waterGoal == 8)
        #expect(decoded.meditatedToday == false)
        #expect(decoded.moodToday == nil)
        #expect(decoded.lifeScore == 50)
    }

    @Test func decodesPartiallyUpgradedLegacySnapshotWithShoppingButNoTodayState() throws {
        // A mid-migration build wrote shopping/agentReply but not the newer
        // today-state fields — every new field must still default cleanly.
        let legacy = """
        {"lifeScore":50,"bestEmoji":"🫀","bestName":"Health","needsFocusEmoji":"💰",\
        "needsFocusName":"Finance","topFocus":[],"shopping":[],\
        "agentReply":"Hi","updatedAt":0}
        """
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(legacy.utf8))
        #expect(decoded.agentReply == "Hi")
        #expect(decoded.agentReplyAt == nil)
        #expect(decoded.captureResults.isEmpty)
        #expect(decoded.waterToday == 0)
        #expect(decoded.waterGoal == 8)
        #expect(decoded.meditatedToday == false)
        #expect(decoded.moodToday == nil)
    }

    @Test func snapshotRoundTripsCaptureResults() throws {
        let snapshot = WidgetSnapshot(
            lifeScore: 65, bestEmoji: "🫀", bestName: "Health",
            needsFocusEmoji: "💰", needsFocusName: "Finance", topFocus: [],
            captureResults: [
                .init(summary: "Logged 1 glass of water", isError: false),
                .init(summary: "Couldn't log that", isError: true),
            ],
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let decoded = try #require(WatchPayload.decode(WatchPayload.encode(snapshot)))
        #expect(decoded == snapshot)
        #expect(decoded.captureResults.map(\.summary) == ["Logged 1 glass of water", "Couldn't log that"])
        #expect(decoded.captureResults.map(\.isError) == [false, true])
    }

    @Test func decodesLegacySnapshotWithoutCaptureResults() throws {
        // A build before capture existed omits the field entirely.
        let legacy = """
        {"lifeScore":50,"bestEmoji":"🫀","bestName":"Health","needsFocusEmoji":"💰",\
        "needsFocusName":"Finance","topFocus":[],"shopping":[],"agentReply":"Hi",\
        "agentReplyAt":100,"waterToday":5,"waterGoal":8,"meditatedToday":true,\
        "moodToday":4,"updatedAt":101}
        """
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(legacy.utf8))
        #expect(decoded.captureResults.isEmpty)
        #expect(decoded.agentReply == "Hi")
    }
}

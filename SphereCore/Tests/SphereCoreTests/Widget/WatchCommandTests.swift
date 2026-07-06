import Testing
@testable import SphereCore

@Suite("WatchCommand")
struct WatchCommandTests {
    @Test func eachCommandRoundTrips() {
        for command in [
            WatchCommand.logWater,
            .logMood(4),
            .logMeditation(minutes: 10),
            .checkShopping(id: "shop_1"),
            .askAgent(query: "How did I sleep?"),
            .capture(text: "drank a glass of water"),
        ] {
            #expect(WatchCommand.decode(command.encode()) == command)
        }
    }

    @Test func decodeRejectsBadPayloads() {
        #expect(WatchCommand.decode([:]) == nil)
        #expect(WatchCommand.decode(["cmd": "unknown"]) == nil)
        // Missing required value.
        #expect(WatchCommand.decode(["cmd": "mood"]) == nil)
        #expect(WatchCommand.decode(["cmd": "meditation"]) == nil)
        #expect(WatchCommand.decode(["cmd": "shopping"]) == nil)
        #expect(WatchCommand.decode(["cmd": "shopping", "id": ""]) == nil)
        #expect(WatchCommand.decode(["cmd": "ask"]) == nil)
        #expect(WatchCommand.decode(["cmd": "capture"]) == nil)
        #expect(WatchCommand.decode(["cmd": "capture", "text": ""]) == nil)
    }
}

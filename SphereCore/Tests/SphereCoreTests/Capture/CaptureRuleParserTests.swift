import Foundation
import Testing
@testable import SphereCore

@Suite("CaptureRuleParser")
struct CaptureRuleParserTests {
    private func single(_ text: String) -> LLMToolCall? {
        let calls = CaptureRuleParser.parse(text)
        return calls.count == 1 ? calls[0] : nil
    }

    @Test func waterWithAndWithoutCount() {
        #expect(single("3 glasses of water")?.name == "log_water_glass")
        #expect(single("3 glasses of water")?.input["count"]?.intValue == 3)
        // Bare keyword defaults to one glass.
        #expect(single("water")?.input["count"]?.intValue == 1)
        // Ukrainian + cap at 12.
        #expect(single("20 склянок води")?.input["count"]?.intValue == 12)
    }

    @Test func weightAcceptsCommaDecimalAndUnits() {
        #expect(single("72.5 kg")?.name == "log_weight")
        #expect(single("72.5 kg")?.input["kg"]?.doubleValue == 72.5)
        #expect(single("вага 72,5")?.input["kg"]?.doubleValue == 72.5)
    }

    @Test func moodClampsToFive() {
        #expect(single("mood 4")?.name == "log_mood")
        #expect(single("mood 4")?.input["score"]?.intValue == 4)
        #expect(single("настрій 9")?.input["score"]?.intValue == 5)
    }

    @Test func meditationMinutes() {
        #expect(single("meditated 10 min")?.name == "log_meditation")
        #expect(single("meditated 10 min")?.input["minutes"]?.intValue == 10)
        #expect(single("медитація 20")?.input["minutes"]?.intValue == 20)
    }

    @Test func spendExtractsAmountTitleCategory() {
        let call = try! #require(single("spent 4.50 on coffee"))
        #expect(call.name == "add_transaction")
        #expect(call.input["amount"]?.doubleValue == 4.5)
        #expect(call.input["type"]?.stringValue == "expense")
        #expect(call.input["category"]?.stringValue == "food")
        #expect(call.input["title"]?.stringValue == "Coffee")
    }

    @Test func spendUkrainianTransport() {
        let call = try! #require(single("витратив 200 на таксі"))
        #expect(call.input["amount"]?.doubleValue == 200)
        #expect(call.input["category"]?.stringValue == "transport")
    }

    @Test func multipleFactsInOneLine() {
        let calls = CaptureRuleParser.parse("coffee spent 4.50, mood 4, water 2")
        let names = Set(calls.map(\.name))
        #expect(names == ["add_transaction", "log_mood", "log_water_glass"])
        #expect(calls.count == 3)
        // Ids are unique per fragment so the registry won't dedupe them.
        #expect(Set(calls.map(\.id)).count == 3)
    }

    @Test func unparseableReturnsEmpty() {
        #expect(CaptureRuleParser.parse("call mom tomorrow").isEmpty)
        #expect(!QuickCapture.canParse("just some thoughts"))
        #expect(QuickCapture.canParse("water 2"))
    }
}

import Testing
@testable import SphereCore

@Suite("sanitizeFtsQuery")
struct FtsQueryTests {
    @Test func quotesTokensAndJoinsWithOr() {
        #expect(sanitizeFtsQuery("react hooks") == "\"react\" OR \"hooks\"")
    }

    @Test func stripsFtsOperatorsAndPunctuation() {
        #expect(sanitizeFtsQuery("\"react\" AND hooks!") == "\"react\" OR \"AND\" OR \"hooks\"")
        #expect(sanitizeFtsQuery("C++ patterns") == "\"C\" OR \"patterns\"")
        #expect(sanitizeFtsQuery("user's notes") == "\"user\" OR \"s\" OR \"notes\"")
    }

    @Test func emptyForPunctuationOnlyInput() {
        #expect(sanitizeFtsQuery("") == "")
        #expect(sanitizeFtsQuery("   ") == "")
        #expect(sanitizeFtsQuery("!@#$%^&*()") == "")
    }

    @Test func preservesUnicodeLetters() {
        #expect(sanitizeFtsQuery("привіт світ") == "\"привіт\" OR \"світ\"")
        #expect(sanitizeFtsQuery("健康 sleep") == "\"健康\" OR \"sleep\"")
    }

    @Test func collapsesRepeatedSeparators() {
        #expect(sanitizeFtsQuery("a  ,  b") == "\"a\" OR \"b\"")
    }
}

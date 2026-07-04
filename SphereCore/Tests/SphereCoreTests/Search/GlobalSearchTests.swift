import Foundation
import Testing
@testable import SphereCore

@Suite("GlobalSearch")
struct GlobalSearchTests {
    private func item(_ sphere: SphereType, _ id: String, _ title: String, _ sub: String = "") -> SearchItem {
        SearchItem(id: id, sphere: sphere, title: title, subtitle: sub)
    }

    @Test func matchesTitleCaseInsensitively() {
        let items = [item(.goals, "1", "Run a 10k"), item(.finance, "2", "Netflix")]
        let hits = GlobalSearch.rank(query: "netflix", items: items)
        #expect(hits.count == 1)
        #expect(hits.first?.id == "2")
    }

    @Test func emptyQueryReturnsNothing() {
        let items = [item(.goals, "1", "Run a 10k")]
        #expect(GlobalSearch.rank(query: "   ", items: items).isEmpty)
    }

    @Test func requiresAllTokens() {
        let items = [
            item(.career, "1", "Prepare quarterly review"),
            item(.career, "2", "Quarterly taxes"),
        ]
        let hits = GlobalSearch.rank(query: "quarterly review", items: items)
        #expect(hits.map(\.id) == ["1"])
    }

    @Test func titleMatchOutranksBodyMatch() {
        let titleHit = item(.learning, "t", "Swift concurrency")
        let bodyHit = item(.learning, "b", "Old notes", "some swift trivia")
        let hits = GlobalSearch.rank(query: "swift", items: [bodyHit, titleHit])
        #expect(hits.first?.id == "t")
    }

    @Test func prefixMatchBoostsRank() {
        let prefix = item(.home, "p", "Garden hose")
        let mid = item(.home, "m", "Rose garden")
        let hits = GlobalSearch.rank(query: "gard", items: [mid, prefix])
        #expect(hits.first?.id == "p")
    }

    @Test func matchesSubtitleKeywords() {
        let items = [SearchItem(id: "1", sphere: .health, title: "Vitamin D", keywords: "supplement bloodwork")]
        #expect(GlobalSearch.rank(query: "bloodwork", items: items).count == 1)
    }

    @Test func respectsLimit() {
        let items = (0..<10).map { item(.goals, "\($0)", "Task \($0) alpha") }
        #expect(GlobalSearch.rank(query: "alpha", items: items, limit: 3).count == 3)
    }

    @Test func groupsBySphereInBestHitOrder() {
        let hits = [
            item(.finance, "f1", "Netflix bill"),
            item(.goals, "g1", "Netflix documentary goal"),
            item(.finance, "f2", "Netflix gift card"),
        ]
        let grouped = GlobalSearch.grouped(hits)
        #expect(grouped.map(\.sphere) == [.finance, .goals])
        #expect(grouped.first?.items.count == 2)
    }
}

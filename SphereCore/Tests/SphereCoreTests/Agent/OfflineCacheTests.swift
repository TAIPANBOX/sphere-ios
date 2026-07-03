import Foundation
import Testing
@testable import SphereCore

@Suite("FileOfflineCache")
struct OfflineCacheTests {
    private func makeCache() -> FileOfflineCache {
        FileOfflineCache(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("engram-cache-tests-\(UUID().uuidString)")
        )
    }

    @Test func briefRoundTrips() async {
        let cache = makeCache()
        #expect(await cache.loadBrief() == nil)
        await cache.saveBrief("Good morning, Yuko")
        #expect(await cache.loadBrief() == "Good morning, Yuko")
    }

    @Test func insightRoundTrips() async {
        let cache = makeCache()
        #expect(await cache.loadInsight() == nil)
        let insight = AgentInsight(insight: "Прогулянки покращують сон", tags: ["rest"])
        await cache.saveInsight(insight)
        #expect(await cache.loadInsight() == insight)
    }
}

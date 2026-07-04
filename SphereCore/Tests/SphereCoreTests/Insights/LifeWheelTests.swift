import Foundation
import Testing
@testable import SphereCore

@Suite("LifeWheel")
struct LifeWheelTests {
    @Test func deltaScalesRatingToHundred() {
        let deltas = LifeWheel.deltas(
            selfRatings: [.health: 8],
            computed: [.health: 60]
        )
        #expect(deltas.count == 1)
        #expect(deltas[0].feeling == 80)
        #expect(deltas[0].data == 60)
        #expect(deltas[0].delta == 20)
    }

    @Test func skipsSpheresWithoutComputedScore() {
        let deltas = LifeWheel.deltas(
            selfRatings: [.health: 7, .creativity: 9],
            computed: [.health: 50]
        )
        #expect(deltas.count == 1)
        #expect(deltas[0].sphere == .health)
    }

    @Test func sortsByWidestGapFirst() {
        let deltas = LifeWheel.deltas(
            selfRatings: [.health: 5, .finance: 2, .mindfulness: 6],
            computed: [.health: 55, .finance: 90, .mindfulness: 58]
        )
        // finance gap = 20-90 = -70 (widest), health = -5, mindfulness = +2.
        #expect(deltas.first?.sphere == .finance)
        #expect(abs(deltas[0].delta) >= abs(deltas[1].delta))
        #expect(abs(deltas[1].delta) >= abs(deltas[2].delta))
    }

    @Test func insightWhenGapIsWideAndNegative() {
        let deltas = LifeWheel.deltas(selfRatings: [.finance: 3], computed: [.finance: 80])
        let insight = LifeWheel.insight(deltas)
        #expect(insight?.contains("worse about Finance") == true)
    }

    @Test func insightPositiveWhenFeelingBeatsData() {
        let deltas = LifeWheel.deltas(selfRatings: [.health: 9], computed: [.health: 50])
        let insight = LifeWheel.insight(deltas)
        #expect(insight?.contains("better about Health") == true)
    }

    @Test func noInsightWhenGapIsSmall() {
        let deltas = LifeWheel.deltas(selfRatings: [.health: 6], computed: [.health: 55])
        #expect(LifeWheel.insight(deltas) == nil)
    }
}

import Testing
@testable import SphereCore

@Suite("Momentum")
struct MomentumTests {
    @Test func streakBands() {
        #expect(Momentum.forStreak(0) == .dormant)
        #expect(Momentum.forStreak(2) == .starting)
        #expect(Momentum.forStreak(5) == .building)
        #expect(Momentum.forStreak(9) == .rolling)
        #expect(Momentum.forStreak(40) == .thriving)
    }

    @Test func streakPhrase() {
        #expect(Momentum.streakPhrase(0) == "Start today")
        #expect(Momentum.streakPhrase(1) == "Getting going · 1 day")
        #expect(Momentum.streakPhrase(9) == "On a roll · 9 days")
    }

    @Test func progressBands() {
        #expect(Momentum.forProgress(0) == .dormant)
        #expect(Momentum.forProgress(10) == .starting)
        #expect(Momentum.forProgress(45) == .building)
        #expect(Momentum.forProgress(80) == .rolling)
        #expect(Momentum.forProgress(100) == .thriving)
    }

    @Test func progressPhraseReframesPercent() {
        #expect(Momentum.progressPhrase(0).contains("one small step"))
        #expect(Momentum.progressPhrase(45) == "Building momentum")
        #expect(Momentum.progressPhrase(100) == "Done")
        #expect(Momentum.progressPhrase(95) == "Almost there")
    }

    @Test func bandsAreOrdered() {
        #expect(MomentumBand.dormant < MomentumBand.thriving)
        #expect(Momentum.forStreak(40).emoji == "⭐️")
    }
}

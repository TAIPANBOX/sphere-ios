import Foundation
import Testing
@testable import SphereCore

@Suite("ReadinessEngine")
struct ReadinessEngineTests {
    @Test func rawScoreRewardsSleepAndLowStress() {
        // 8h vs 8h goal (60) + stress 0 (40) = 100.
        #expect(ReadinessEngine.rawScore(sleepHours: 8, sleepGoal: 8, stress: 0) == 100)
        // 4h (30) + stress 10 (0) = 30.
        #expect(ReadinessEngine.rawScore(sleepHours: 4, sleepGoal: 8, stress: 10) == 30)
        // Unknown stress contributes the neutral 20.
        #expect(ReadinessEngine.rawScore(sleepHours: 8, sleepGoal: 8, stress: nil) == 80)
    }

    @Test func highScoreYieldsHighBandAndPushMessage() {
        let v = ReadinessEngine.verdict(ReadinessInput(sleepHours: 8, sleepGoal: 8, stress: 1))
        #expect(v.band == .high)
        #expect(v.recommendation.contains("push"))
    }

    @Test func lowScoreYieldsGentleMessageAndShorterWindow() {
        let v = ReadinessEngine.verdict(
            ReadinessInput(sleepHours: 4, sleepGoal: 8, stress: 9, wakeHour: 7)
        )
        #expect(v.band == .low)
        #expect(v.recommendation.contains("gentle"))
        // Low band → 1h window pushed to wake+3: 10 AM–11 AM.
        #expect(v.focusWindow == "10 AM–11 AM")
    }

    @Test func focusWindowIsTwoHoursAfterWakePlusTwo() {
        let v = ReadinessEngine.verdict(ReadinessInput(sleepHours: 8, sleepGoal: 8, stress: 1, wakeHour: 7))
        #expect(v.focusWindow == "9 AM–11 AM")
    }

    @Test func focusWindowCrossesNoonCorrectly() {
        // wake 11 → start 13, end 15 → "1 PM–3 PM".
        #expect(ReadinessEngine.focusWindow(wakeHour: 11, band: .high) == "1 PM–3 PM")
    }

    @Test func windDownIsThirtyMinutesBeforeBedtime() {
        #expect(ReadinessEngine.windDown(bedtimeHour: 23, bedtimeMinute: 0) == "22:30")
        // Wraps past midnight: 00:15 bedtime → 23:45.
        #expect(ReadinessEngine.windDown(bedtimeHour: 0, bedtimeMinute: 15) == "23:45")
    }

    @Test func correctionZeroUntilEnoughOverlap() {
        let predicted = ["2026-06-01": 80, "2026-06-02": 80]
        let felt = ["2026-06-01": 3, "2026-06-02": 3]
        #expect(ReadinessEngine.correction(predicted: predicted, felt: felt) == 0)
    }

    @Test func correctionPullsTowardFeltEnergy() {
        // Predicted 80 but felt 3/5 (=60) for 3 days → offset −20, clamped to −15.
        let predicted = ["2026-06-01": 80, "2026-06-02": 80, "2026-06-03": 80]
        let felt = ["2026-06-01": 3, "2026-06-02": 3, "2026-06-03": 3]
        #expect(ReadinessEngine.correction(predicted: predicted, felt: felt) == -15)
    }

    @Test func correctionAppliesToFinalScore() {
        // raw 80, correction pulls down 15 → 65 (moderate not high).
        let predicted = ["2026-06-01": 80, "2026-06-02": 80, "2026-06-03": 80]
        let felt = ["2026-06-01": 3, "2026-06-02": 3, "2026-06-03": 3]
        let corr = ReadinessEngine.correction(predicted: predicted, felt: felt)
        let v = ReadinessEngine.verdict(
            ReadinessInput(sleepHours: 8, sleepGoal: 8, stress: nil, correction: corr)
        )
        #expect(v.score == 65)
        #expect(v.band == .moderate)
    }
}

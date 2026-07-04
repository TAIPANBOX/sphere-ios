import Foundation
import Testing
@testable import SphereCore

@Suite("DisciplineScore")
struct DisciplineScoreTests {
    @Test func fullScoreWhenEverythingDone() {
        // 60 min focus (goal) + meditated + 7-day streak → 50 + 25 + 25 = 100.
        #expect(DisciplineScore.compute(focusMinutesToday: 60, meditatedToday: true, focusStreakDays: 7) == 100)
    }

    @Test func focusOnlyHalfWhenAtGoal() {
        #expect(DisciplineScore.compute(focusMinutesToday: 60, meditatedToday: false, focusStreakDays: 0) == 50)
    }

    @Test func partialFocusScalesLinearly() {
        // 30/60 focus = 25 pts; no meditation; streak 0.
        #expect(DisciplineScore.compute(focusMinutesToday: 30, meditatedToday: false, focusStreakDays: 0) == 25)
    }

    @Test func zeroWhenNothing() {
        #expect(DisciplineScore.compute(focusMinutesToday: 0, meditatedToday: false, focusStreakDays: 0) == 0)
    }

    @Test func breathingPatternsHaveTiming() {
        #expect(BreathingPattern.box.timing == (4, 4, 4, 4))
        #expect(BreathingPattern.coherent.timing.holdIn == 0)
        #expect(BreathingPattern.allCases.count == 3)
    }
}

@Suite("Focus sessions in MindfulnessStore")
@MainActor
struct FocusSessionTests {
    @Test func focusLogsFeedMinutesStreakAndScore() async throws {
        let database = try AppDatabase.inMemory()
        let store = MindfulnessStore(database: database)
        try await store.load()

        #expect(store.disciplineScore() == 0)
        try await store.logFocusSession(minutes: 30)
        #expect(store.focusMinutesToday() == 30)
        #expect(store.hasFocusedToday())
        #expect(store.focusStreak() == 1)

        // Focus sessions don't count as meditation streak.
        #expect(store.currentStreak() == 0)

        // 30 min focus (25 pts) + streak 1/7 (~4 pts) = ~29.
        #expect(store.disciplineScore() >= 25)

        let reloaded = MindfulnessStore(database: database)
        try await reloaded.load()
        #expect(reloaded.focusSessions.count == 1)
    }
}

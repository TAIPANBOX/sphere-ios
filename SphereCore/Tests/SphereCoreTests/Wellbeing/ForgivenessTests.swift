import Foundation
import Testing
@testable import SphereCore

@Suite("StreakPolicy")
struct StreakPolicyTests {
    private let cal = DayKey.calendar
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func key(_ y: Int, _ m: Int, _ d: Int) -> String { DayKey.make(day(y, m, d)) }

    @Test func countsConsecutiveActiveDaysEndingToday() {
        let active: Set<String> = [key(2026, 7, 4), key(2026, 7, 3), key(2026, 7, 2)]
        let streak = StreakPolicy.streak(
            asOf: day(2026, 7, 4), isActive: { active.contains(DayKey.make($0)) }
        )
        #expect(streak == 3)
    }

    @Test func todayNotDoneGivesZeroWithoutExcuse() {
        let active: Set<String> = [key(2026, 7, 3), key(2026, 7, 2)]
        let streak = StreakPolicy.streak(
            asOf: day(2026, 7, 4), isActive: { active.contains(DayKey.make($0)) }
        )
        #expect(streak == 0)
    }

    @Test func excusedDaysBridgeWithoutIncrementing() {
        // Active Jul 1-2, then sick Jul 3-4 (no sessions). Streak stays 2.
        let active: Set<String> = [key(2026, 7, 2), key(2026, 7, 1)]
        let excused: Set<String> = [key(2026, 7, 4), key(2026, 7, 3)]
        let streak = StreakPolicy.streak(
            asOf: day(2026, 7, 4),
            isActive: { active.contains(DayKey.make($0)) },
            isExcused: { excused.contains(DayKey.make($0)) }
        )
        #expect(streak == 2)
    }

    @Test func gapOutsideExcuseStillBreaks() {
        let active: Set<String> = [key(2026, 7, 4), key(2026, 7, 2)] // Jul 3 missing
        let streak = StreakPolicy.streak(
            asOf: day(2026, 7, 4), isActive: { active.contains(DayKey.make($0)) }
        )
        #expect(streak == 1)
    }
}

@Suite("Forgiveness — focus + excused days")
struct ForgivenessIntegrationTests {
    private let cal = DayKey.calendar
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func pausedFocusDropsDailyNags() {
        let metrics = HealthMetrics(
            steps: 100, heartRate: 60, sleepHours: 7, calories: 100, hrv: 40,
            weeklySteps: [0, 0, 0, 0, 0, 0, 100]
        )
        let normal = FocusBuilder.build(
            careerTasks: [], goals: [], metrics: metrics,
            hasMeditatedToday: false, isPaused: false
        )
        let paused = FocusBuilder.build(
            careerTasks: [], goals: [], metrics: metrics,
            hasMeditatedToday: false, isPaused: true
        )
        #expect(normal.contains { $0.id == "mindfulness_daily" })
        #expect(normal.contains { $0.id == "health_steps" })
        // Paused: no meditation nag, no steps nag, no generic fallbacks.
        #expect(!paused.contains { $0.id == "mindfulness_daily" })
        #expect(!paused.contains { $0.id == "health_steps" })
        #expect(!paused.contains { $0.id == "hydration" })
        #expect(paused.isEmpty)
    }

    @Test func pausedStillShowsRealCommitments() {
        let birthday = day(2026, 7, 4)
        let contact = Contact(id: "c1", name: "Iryna", birthday: birthday)
        let paused = FocusBuilder.build(
            careerTasks: [], goals: [], metrics: nil,
            contacts: [contact], isPaused: true, now: birthday
        )
        #expect(paused.contains { $0.sphere == .relationships })
    }

    @Test func profileExcusedDaysSpanThePause() {
        var profile = UserProfile()
        profile.wellbeingMode = .sick
        profile.wellbeingSince = day(2026, 7, 2)
        profile.wellbeingUntil = day(2026, 7, 5)
        let excused = profile.wellbeingExcusedDays(asOf: day(2026, 7, 4))
        // From since (Jul 2) through today (Jul 4, capped by "until" >= today).
        #expect(excused == [
            DayKey.make(day(2026, 7, 2)),
            DayKey.make(day(2026, 7, 3)),
            DayKey.make(day(2026, 7, 4)),
        ])
        // Not paused → empty.
        var normal = profile
        normal.wellbeingMode = .normal
        #expect(normal.wellbeingExcusedDays(asOf: day(2026, 7, 4)).isEmpty)
    }
}

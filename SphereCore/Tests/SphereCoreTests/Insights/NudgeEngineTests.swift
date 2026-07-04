import Foundation
import Testing
@testable import SphereCore

@Suite("NudgeEngine rules")
struct NudgeEngineTests {
    private func ctx(_ mutate: (inout NudgeContext) -> Void) -> NudgeContext {
        var c = NudgeContext(now: Date(), hour: 10)
        mutate(&c)
        return c
    }

    @Test func stressReliefFiresOnThreeHighDaysNoMeditation() {
        let fire = NudgeEngine.evaluate(ctx { $0.recentStress = [8, 7, 9]; $0.meditatedToday = false })
        #expect(fire.contains { $0.id == "stress_relief" })
        // Meditated today → suppressed.
        let noFire = NudgeEngine.evaluate(ctx { $0.recentStress = [8, 7, 9]; $0.meditatedToday = true })
        #expect(!noFire.contains { $0.id == "stress_relief" })
        // Only two high days → no fire.
        let short = NudgeEngine.evaluate(ctx { $0.recentStress = [7, 8] })
        #expect(!short.contains { $0.id == "stress_relief" })
    }

    @Test func budgetWarningFiresBeforeDay24() {
        let fire = NudgeEngine.evaluate(ctx { $0.monthlyBudgetTotal = 1000; $0.spentThisMonth = 950; $0.dayOfMonth = 15 })
        #expect(fire.contains { $0.id == "budget_warning" })
        // Late in the month → no warning (it's expected by then).
        let late = NudgeEngine.evaluate(ctx { $0.monthlyBudgetTotal = 1000; $0.spentThisMonth = 950; $0.dayOfMonth = 28 })
        #expect(!late.contains { $0.id == "budget_warning" })
    }

    @Test func streakLapseOnlyInEvening() {
        let evening = NudgeEngine.evaluate(ctx { $0.hour = 20; $0.meditationStreak = 5; $0.meditatedToday = false })
        #expect(evening.contains { $0.id == "streak_lapse" })
        let morning = NudgeEngine.evaluate(ctx { $0.hour = 9; $0.meditationStreak = 5; $0.meditatedToday = false })
        #expect(!morning.contains { $0.id == "streak_lapse" })
    }

    @Test func sleepDebtPlantAndContactRules() {
        let fired = NudgeEngine.evaluate(ctx {
            $0.sleepDebtHours = 7
            $0.staleContact = ("Iryna", 74)
            $0.thirstyPlant = ("Ficus", 3)
        })
        #expect(Set(fired.map(\.id)).isSuperset(of: ["sleep_debt", "stale_contact", "plant_water"]))
        // Plant only 1 day overdue → no fire.
        let plantOk = NudgeEngine.evaluate(ctx { $0.thirstyPlant = ("Ficus", 1) })
        #expect(!plantOk.contains { $0.id == "plant_water" })
    }
}

@Suite("NudgeScheduler cooldown + daily cap")
struct NudgeSchedulerTests {
    private let cal = DayKey.calendar
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func nudge(_ id: String, priority: Int, cooldown: Int) -> Nudge {
        Nudge(id: id, priority: priority, title: id, body: id, cooldownDays: cooldown)
    }

    @Test func picksHighestPriority() {
        let picked = NudgeScheduler.select(
            candidates: [nudge("a", priority: 40, cooldown: 1), nudge("b", priority: 90, cooldown: 1)],
            lastFired: [:], now: date(2026, 7, 4)
        )
        #expect(picked?.id == "b")
    }

    @Test func respectsPerRuleCooldown() {
        let now = date(2026, 7, 4)
        // b fired 1 day ago but cooldown is 5 → only a is eligible.
        let picked = NudgeScheduler.select(
            candidates: [nudge("a", priority: 40, cooldown: 1), nudge("b", priority: 90, cooldown: 5)],
            lastFired: ["b": date(2026, 7, 3)], now: now
        )
        #expect(picked?.id == "a")
    }

    @Test func globalDailyCapBlocksSecondNudge() {
        let now = date(2026, 7, 4)
        // Something already fired today → nothing else today.
        let picked = NudgeScheduler.select(
            candidates: [nudge("a", priority: 40, cooldown: 1)],
            lastFired: ["x": now], now: now
        )
        #expect(picked == nil)
    }
}

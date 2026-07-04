import Foundation
import Testing
@testable import SphereCore

@Suite("LifeScore")
struct LifeScoreTests {
    @Test func healthFormulaWeightsStepsAndSleep() {
        let metrics = HealthMetrics(
            steps: 5_000, heartRate: 60, sleepHours: 8, calories: 0, hrv: 0,
            weeklySteps: []
        )
        let score = LifeScore.health(metrics: metrics)
        // 0.5 * 0.6 + 1.0 * 0.4 = 0.7
        #expect(abs(score.score - 0.7) < 1e-9)
        #expect(score.insight == "5.0k steps · 8h sleep")

        #expect(LifeScore.health(metrics: nil).score == 0.75)
    }

    @Test func careerFormulaPenalizesOverdue() {
        let now = Date()
        let done = CareerTask(id: "d", title: "Done", status: .done, createdAt: now)
        let open = CareerTask(id: "o", title: "Open", createdAt: now)
        let late = CareerTask(
            id: "l", title: "Late",
            dueDate: now.addingTimeInterval(-86_400), createdAt: now
        )

        // 1 of 2 done, none overdue: 0.5*0.6 + 1.0*0.4 = 0.7
        let clean = LifeScore.career(tasks: [done, open], now: now)
        #expect(abs(clean.score - 0.7) < 1e-9)

        // 1 of 3 done, one overdue: (1/3)*0.6 + 0.4*0.4 = 0.36
        let withOverdue = LifeScore.career(tasks: [done, open, late], now: now)
        #expect(abs(withOverdue.score - 0.36) < 1e-9)
        #expect(withOverdue.insight.contains("1 overdue"))

        // Empty defaults to the optimistic 0.85.
        #expect(LifeScore.career(tasks: [], now: now).score == 0.85)
    }

    @Test func financeFormulaTracksSavingsRate() {
        // Savings rate 0.4 → 0.3 + 0.4*0.7 = 0.58
        let score = LifeScore.finance(totalIncome: 1_000, totalExpenses: 600)
        #expect(abs(score.score - 0.58) < 1e-9)
        #expect(score.insight == "Saving 40% of income")

        let overspending = LifeScore.finance(totalIncome: 1_000, totalExpenses: 1_500)
        #expect(abs(overspending.score - 0.3) < 1e-9)
        #expect(overspending.insight == "Spending exceeds income")

        #expect(LifeScore.finance(totalIncome: 0, totalExpenses: 0).score == 0.5)
    }

    @Test func goalsFormulaAveragesActiveOnly() {
        let goals = [
            Goal(id: "g1", title: "A", progressPercent: 80),
            Goal(id: "g2", title: "B", progressPercent: 40),
            Goal(id: "g3", title: "C", status: .paused, progressPercent: 0),
        ]
        let score = LifeScore.goalsScore(goals: goals)
        #expect(abs(score.score - 0.6) < 1e-9)
        #expect(score.insight == "2 active · 60% avg progress")
    }

    @Test func relationshipsFormulaTracksCheckins() {
        let now = Date()
        #expect(LifeScore.relationships(contacts: [], now: now).score == 0.75)

        let caughtUp = Contact(id: "c1", name: "A", lastContact: now)
        let overdue = Contact(id: "c2", name: "B", lastContact: now.addingTimeInterval(-40 * 86_400))
        #expect(LifeScore.relationships(contacts: [caughtUp], now: now).score == 0.9)

        // 1 of 2 needs check-in: 1 - (1/2)*0.5 = 0.75
        let mixed = LifeScore.relationships(contacts: [caughtUp, overdue], now: now)
        #expect(abs(mixed.score - 0.75) < 1e-9)
        #expect(mixed.insight == "2 people · 1 need a check-in")
    }

    @Test func restFormulaTracksSleepVsGoal() {
        #expect(LifeScore.rest(avgSleepHours: 0, avgRecovery: .good).score == 0.5)

        let good = LifeScore.rest(avgSleepHours: 7.2, avgRecovery: .good)
        #expect(abs(good.score - 0.9) < 1e-9)
        #expect(good.insight == "7.2h avg sleep · Good recovery")

        // Clamped to 0.2 at the bottom, 1.0 at the top.
        #expect(LifeScore.rest(avgSleepHours: 1, avgRecovery: .poor).score == 0.2)
        #expect(LifeScore.rest(avgSleepHours: 10, avgRecovery: .excellent).score == 1)
    }

    @Test func hobbiesFormulaTracksWeeklyMinutes() {
        #expect(LifeScore.hobbies(count: 0, weeklyMinutes: 0).score == 0.5)
        // 150 of the 300-min reference week.
        #expect(abs(LifeScore.hobbies(count: 2, weeklyMinutes: 150).score - 0.5) < 1e-9)
        // No time logged clamps to the 0.1 floor.
        #expect(abs(LifeScore.hobbies(count: 2, weeklyMinutes: 0).score - 0.1) < 1e-9)
    }

    @Test func overallBestAndNeedsFocus() {
        let scores = LifeScore.compute(
            metrics: nil,
            books: [Book(id: "b", title: "T", totalPages: 100, status: .reading)],
            careerTasks: [],
            totalIncome: 1_000,
            totalExpenses: 600,
            goals: []
        )
        #expect(scores.count == 8)
        // health .75, learning .6, career .85, finance .58,
        // relationships .75, rest .5, hobbies .5, goals .5
        #expect(abs(LifeScore.overall(scores) - 0.62875) < 1e-9)
        #expect(LifeScore.best(scores)?.sphere == .career)
        // First of the tied 0.5 spheres in display order.
        #expect(LifeScore.needsFocus(scores)?.sphere == .rest)
    }
}

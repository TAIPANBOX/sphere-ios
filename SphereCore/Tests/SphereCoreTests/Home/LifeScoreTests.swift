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

    @Test func overallBestAndNeedsFocus() {
        let scores = LifeScore.compute(
            metrics: nil,
            books: [Book(id: "b", title: "T", totalPages: 100, status: .reading)],
            careerTasks: [],
            totalIncome: 1_000,
            totalExpenses: 600,
            goals: []
        )
        #expect(scores.count == 5)
        // health 0.75, learning 0.6, career 0.85, finance 0.58, goals 0.5
        #expect(abs(LifeScore.overall(scores) - 0.656) < 1e-9)
        #expect(LifeScore.best(scores)?.sphere == .career)
        #expect(LifeScore.needsFocus(scores)?.sphere == .goals)
    }
}

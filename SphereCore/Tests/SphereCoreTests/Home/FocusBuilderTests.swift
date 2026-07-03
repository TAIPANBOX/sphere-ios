import Foundation
import Testing
@testable import SphereCore

@Suite("FocusBuilder")
struct FocusBuilderTests {
    private let now = Date()

    private func task(
        _ id: String, _ title: String,
        priority: TaskPriority = .medium,
        status: TaskStatus = .todo,
        due: Date? = nil
    ) -> CareerTask {
        CareerTask(id: id, title: title, priority: priority, status: status, dueDate: due, createdAt: now)
    }

    @Test func overdueTasksComeFirstWithDayCount() {
        let items = FocusBuilder.build(
            careerTasks: [task("t1", "Ship it", due: now.addingTimeInterval(-2 * 86_400))],
            goals: [],
            metrics: nil,
            now: now
        )
        let first = items[0]
        #expect(first.id == "overdue_t1")
        #expect(first.urgency == .urgent)
        #expect(first.tag == "Overdue")
        #expect(first.subtitle.contains("Overdue by 2 days"))
    }

    @Test func urgentAndHighPrioritiesRankAboveDaily() {
        let items = FocusBuilder.build(
            careerTasks: [
                task("t1", "Urgent thing", priority: .urgent),
                task("t2", "High one", priority: .high),
                task("t3", "High two", priority: .high),
                task("t4", "High three (dropped)", priority: .high),
            ],
            goals: [],
            metrics: nil,
            now: now
        )
        #expect(items[0].id == "urgent_t1")
        // High tasks capped at 2.
        #expect(items.count(where: { $0.id.hasPrefix("high_") }) == 2)
        let urgencies = items.map(\.urgency.rawValue)
        #expect(urgencies == urgencies.sorted())
    }

    @Test func stuckGoalsSurfaceAsImportant() {
        let items = FocusBuilder.build(
            careerTasks: [],
            goals: [
                Goal(id: "g1", title: "Stuck", progressPercent: 5),
                Goal(id: "g2", title: "Moving", progressPercent: 50),
            ],
            metrics: nil,
            now: now
        )
        let stuck = items.first { $0.id == "goal_g1" }
        #expect(stuck?.urgency == .important)
        #expect(stuck?.tag == "5%")
        #expect(!items.contains { $0.id == "goal_g2" })
    }

    @Test func stepGoalUsesRealRemainingSteps() {
        let metrics = HealthMetrics(
            steps: 8_432, heartRate: 0, sleepHours: 0, calories: 0, hrv: 0, weeklySteps: []
        )
        let items = FocusBuilder.build(careerTasks: [], goals: [], metrics: metrics, now: now)
        let steps = items.first { $0.id == "health_steps" }
        #expect(steps?.subtitle.contains("1,568") == true || steps?.subtitle.contains("1 568") == true)

        let done = HealthMetrics(
            steps: 12_000, heartRate: 0, sleepHours: 0, calories: 0, hrv: 0, weeklySteps: []
        )
        let noSteps = FocusBuilder.build(careerTasks: [], goals: [], metrics: done, now: now)
        #expect(!noSteps.contains { $0.id == "health_steps" })
    }

    @Test func meditationSkippedWhenAlreadyDone() {
        let items = FocusBuilder.build(
            careerTasks: [], goals: [], metrics: nil, hasMeditatedToday: true, now: now
        )
        #expect(!items.contains { $0.id == "mindfulness_daily" })
    }

    @Test func fallbacksFillToFiveItems() {
        let items = FocusBuilder.build(careerTasks: [], goals: [], metrics: nil, now: now)
        #expect(items.count >= 5)
        #expect(items.contains { $0.id == "hydration" })
        // Sorted by urgency throughout.
        let urgencies = items.map(\.urgency.rawValue)
        #expect(urgencies == urgencies.sorted())
    }
}

import Foundation
import Testing
@testable import SphereCore

@Suite("Goals extras: anti-goals, why, habit identity/heatmap/reminders")
@MainActor
struct GoalsExtrasTests {
    private func makeStore() throws -> (GoalsStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (GoalsStore(database: database), database)
    }

    @Test func antiGoalsAndWhyPersist() async throws {
        let (store, database) = try makeStore()
        try await store.load()
        try await store.add(Goal(id: "g", title: "Launch app", progressPercent: 5, why: "Freedom to build"))
        try await store.addAntiGoal(AntiGoal(id: "a", title: "No meetings before noon"))

        #expect(store.stalledGoals().map(\.id) == ["g"]) // < 20%
        #expect(store.goals.first?.why == "Freedom to build")

        let reloaded = GoalsStore(database: database)
        try await reloaded.load()
        #expect(reloaded.antiGoals.count == 1)
        #expect(reloaded.goals.first?.why == "Freedom to build")
    }

    @Test func habitIdentityAndReminderFieldsRoundTrip() async throws {
        let (store, database) = try makeStore()
        try await store.load()
        try await store.addHabit(Habit(
            id: "h", name: "Read", identity: "a reader", reminderWeekdays: [2, 4, 6]
        ))
        let reloaded = GoalsStore(database: database)
        try await reloaded.load()
        #expect(reloaded.habits.first?.identity == "a reader")
        #expect(reloaded.habits.first?.reminderWeekdays == [2, 4, 6])
    }
}

@Suite("Habit heatmap + reminder plans")
struct HabitReminderTests {
    private let cal = DayKey.calendar
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func heatmapReflectsCheckins() {
        var habit = Habit(id: "h", name: "Meditate")
        habit = habit.checkingIn(on: date(2026, 7, 4))
        habit = habit.checkingIn(on: date(2026, 7, 2))
        let map = habit.heatmap(days: 7, asOf: date(2026, 7, 4))
        #expect(map.count == 7)
        #expect(map.last == true)      // today (Jul 4)
        #expect(map[map.count - 3] == true) // Jul 2
        #expect(map[map.count - 2] == false) // Jul 3
    }

    @Test func remindersBuildOnePlanPerHabitWeekday() {
        let habits = [
            Habit(id: "h1", name: "Read", identity: "a reader", reminderWeekdays: [2, 4]),
            Habit(id: "h2", name: "Run", reminderWeekdays: []),  // no reminders
        ]
        let plans = NotificationPlanBuilder.habitReminders(habits, hour: 8)
        #expect(plans.count == 2)  // only h1's two weekdays
        #expect(plans.allSatisfy { $0.category == .habit })
        #expect(plans[0].dateComponents.hour == 8)
        #expect(plans.contains { $0.body.contains("a reader") })
    }
}

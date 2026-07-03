import Foundation
import Testing
@testable import SphereCore

@Suite("Habit")
struct HabitTests {
    private func key(daysAgo: Int, from now: Date) -> String {
        Habit.dateKey(now.addingTimeInterval(Double(-daysAgo) * 86_400))
    }

    @Test func streakCountsConsecutiveDaysEndingToday() {
        let now = Date()
        let habit = Habit(
            id: "h", name: "Read",
            checkInDates: [key(daysAgo: 2, from: now), key(daysAgo: 1, from: now), key(daysAgo: 0, from: now)]
        )
        #expect(habit.streak(asOf: now) == 3)
    }

    @Test func streakSurvivesUncheckedToday() {
        let now = Date()
        let habit = Habit(
            id: "h", name: "Read",
            checkInDates: [key(daysAgo: 2, from: now), key(daysAgo: 1, from: now)]
        )
        #expect(habit.streak(asOf: now) == 2)
    }

    @Test func gapBreaksStreak() {
        let now = Date()
        let habit = Habit(
            id: "h", name: "Read",
            checkInDates: [key(daysAgo: 3, from: now), key(daysAgo: 1, from: now), key(daysAgo: 0, from: now)]
        )
        #expect(habit.streak(asOf: now) == 2)
    }

    @Test func emptyHabitHasZeroStreak() {
        #expect(Habit(id: "h", name: "Read").streak() == 0)
    }

    @Test func checkInIsIdempotent() {
        let habit = Habit(id: "h", name: "Read").checkingIn().checkingIn()
        #expect(habit.checkInDates.count == 1)
        #expect(habit.uncheckingIn().checkInDates.isEmpty)
    }
}

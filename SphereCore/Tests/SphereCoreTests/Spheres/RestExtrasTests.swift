import Foundation
import Testing
@testable import SphereCore

@Suite("SleepMath: sleep debt")
struct SleepMathTests {
    @Test func accumulatesDeficitBelowGoal() {
        // Goal 8h; nights 6, 7, 8, 9 → deficits 2 + 1 + 0 + 0 = 3.
        #expect(SleepMath.sleepDebt(hoursByNight: [6, 7, 8, 9], goal: 8) == 3)
    }

    @Test func zeroWhenAllAtGoalOrNoGoal() {
        #expect(SleepMath.sleepDebt(hoursByNight: [8, 9], goal: 8) == 0)
        #expect(SleepMath.sleepDebt(hoursByNight: [4, 5], goal: 0) == 0)
    }
}

@Suite("Rest extras: naps, recovery, vacation, sleep debt")
@MainActor
struct RestExtrasTests {
    private func makeStore() throws -> (RestStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (RestStore(database: database), database)
    }

    @Test func napsAndRecoveryPersist() async throws {
        let (store, database) = try makeStore()
        try await store.load()
        try await store.addNap(Nap(id: "n", date: Date(), minutes: 25))
        try await store.addRecoveryActivity(RecoveryActivity(id: "r1", name: "Walk", rating: 4))
        try await store.addRecoveryActivity(RecoveryActivity(id: "r2", name: "Bath", rating: 5))

        // Sorted by rating desc.
        #expect(store.recoveryActivities.first?.name == "Bath")

        let reloaded = RestStore(database: database)
        try await reloaded.load()
        #expect(reloaded.naps.count == 1)
        #expect(reloaded.recoveryActivities.count == 2)
    }

    @Test func vacationLedgerCountsAndRemaining() async throws {
        let (store, _) = try makeStore()
        try await store.load()
        let cal = DayKey.calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 4))!
        let sameYear = cal.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let lastYear = cal.date(from: DateComponents(year: 2025, month: 12, day: 20))!

        try await store.toggleVacation(on: now)
        try await store.toggleVacation(on: sameYear)
        try await store.toggleVacation(on: lastYear)

        #expect(store.usedVacationDays(asOf: now) == 2) // last-year one excluded
        #expect(store.remainingVacationDays(allowance: 25, asOf: now) == 23)
        #expect(store.isVacationDay(now))

        try await store.toggleVacation(on: now) // untoggle
        #expect(store.usedVacationDays(asOf: now) == 1)
    }

    @Test func sleepDebtUsesScheduleGoal() async throws {
        let (store, _) = try makeStore()
        try await store.load()
        try await store.setGoal(hours: 8)
        try await store.add(SleepEntry(id: "s1", date: Date(), hoursSlept: 6, recovery: .fair))
        try await store.add(SleepEntry(id: "s2", date: Date().addingTimeInterval(-86_400), hoursSlept: 7, recovery: .good))
        #expect(store.sleepDebtLast7() == 3) // (8-6)+(8-7)
    }
}

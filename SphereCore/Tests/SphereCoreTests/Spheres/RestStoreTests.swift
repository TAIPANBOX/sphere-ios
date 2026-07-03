import Foundation
import Testing
@testable import SphereCore

@Suite("RestStore")
@MainActor
struct RestStoreTests {
    private func makeStore(engram: EngramStore? = nil) throws -> (RestStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (RestStore(database: database, engram: engram), database)
    }

    private func entry(
        _ id: String, hours: Double,
        recovery: RecoveryLevel = .good,
        daysAgo: Int = 0,
        from now: Date = Date()
    ) -> SleepEntry {
        SleepEntry(
            id: id, date: now.addingTimeInterval(Double(-daysAgo) * 86_400),
            hoursSlept: hours, recovery: recovery
        )
    }

    // MARK: - Sleep log

    @Test func sleepAveragesUseLast7DaysOnly() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        try await store.add(entry("s1", hours: 8, recovery: .excellent, daysAgo: 1, from: now))
        try await store.add(entry("s2", hours: 6, recovery: .fair, daysAgo: 3, from: now))
        try await store.add(entry("s3", hours: 4, recovery: .poor, daysAgo: 10, from: now))

        #expect(abs(store.avgHoursLast7(asOf: now) - 7) < 1e-9)
        // (4 + 2) / 2 = 3.0 → good
        #expect(store.avgRecoveryLast7(asOf: now) == .good)
        #expect(store.last7(asOf: now).count == 2)
    }

    @Test func recoveryLevelBucketsMatchDart() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        #expect(store.avgRecoveryLast7(asOf: now) == .good)

        try await store.add(entry("s1", hours: 8, recovery: .excellent, daysAgo: 1, from: now))
        try await store.add(entry("s2", hours: 8, recovery: .excellent, daysAgo: 2, from: now))
        #expect(store.avgRecoveryLast7(asOf: now) == .excellent)

        try await store.add(entry("s3", hours: 8, recovery: .poor, daysAgo: 3, from: now))
        // (4+4+1)/3 = 3.0 → good
        #expect(store.avgRecoveryLast7(asOf: now) == .good)
    }

    @Test func recoveryScoreFormulaMatchesFlutterScreen() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        try await store.add(entry("s1", hours: 8, daysAgo: 1, from: now))

        // Full sleep, unknown stress: 60 + 20 = 80.
        #expect(store.recoveryScore(asOf: now) == 80)
        // Full sleep, zero stress: 60 + 40 = 100.
        #expect(store.recoveryScore(stressLevel: 0, asOf: now) == 100)
        // Full sleep, max stress: 60 + 0 = 60.
        #expect(store.recoveryScore(stressLevel: 10, asOf: now) == 60)

        let (empty, _) = try makeStore()
        #expect(empty.recoveryScore(asOf: now) == 20)
    }

    @Test func sleepPersistsNewestFirstAndNotesEngram() async throws {
        let engram = try EngramStore.inMemory()
        let (store, database) = try makeStore(engram: engram)
        try await store.add(entry("s1", hours: 7.5, recovery: .good, daysAgo: 1))
        try await store.add(entry("s2", hours: 6, recovery: .fair))

        let reloaded = RestStore(database: database)
        try await reloaded.load()
        #expect(reloaded.sleepEntries.map(\.id) == ["s2", "s1"])

        var count = 0
        for _ in 0..<50 where count < 2 {
            count = try await engram.count(agentId: "rest")
            if count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        }
        let memories = try await engram.recall("slept", agentId: "rest")
        #expect(memories.contains { $0.content == "Slept 7.5h, felt good" })
    }

    // MARK: - Schedule

    @Test func scheduleRoundTripsAndRollsOverMidnight() async throws {
        let (store, database) = try makeStore()
        try await store.load()
        try await store.setBedtime(hour: 23, minute: 30)
        try await store.setWakeTime(hour: 6, minute: 45)
        try await store.setGoal(hours: 7.5)
        try await store.toggleReminders()

        #expect(abs(store.schedule.scheduledHours - 7.25) < 1e-9)
        #expect(store.schedule.bedtimeLabel == "23:30")

        let reloaded = RestStore(database: database)
        try await reloaded.load()
        #expect(reloaded.schedule.wakeLabel == "06:45")
        #expect(reloaded.schedule.goalHours == 7.5)
        #expect(reloaded.schedule.remindersEnabled)
    }

    // MARK: - Detox & work hours

    @Test func detoxToggleAndStreak() async throws {
        let now = Date()
        let (store, database) = try makeStore()
        try await store.toggleDetox(on: now)
        try await store.toggleDetox(on: now.addingTimeInterval(-86_400))

        #expect(store.isDetoxDay(now))
        #expect(store.detoxStreak(asOf: now) == 2)

        try await store.toggleDetox(on: now)
        #expect(!store.isDetoxDay(now))
        #expect(store.detoxStreak(asOf: now) == 0)

        let reloaded = RestStore(database: database)
        try await reloaded.load()
        #expect(reloaded.detoxStreak(asOf: now.addingTimeInterval(-86_400)) == 1)
    }

    @Test func workHoursUpsertAndWeeklyTotal() async throws {
        let now = Date()
        let (store, database) = try makeStore()
        try await store.logWorkHours(8, on: now)
        try await store.logWorkHours(9, on: now)
        try await store.logWorkHours(10, on: now.addingTimeInterval(-86_400))
        try await store.logWorkHours(5, on: now.addingTimeInterval(-10 * 86_400))

        #expect(store.weeklyWorkHours(asOf: now) == 19)

        let reloaded = RestStore(database: database)
        try await reloaded.load()
        #expect(reloaded.weeklyWorkHours(asOf: now) == 19)
    }

    // MARK: - Weekend plans

    @Test func weekendActivitiesRoundTripPerWeek() async throws {
        let now = Date()
        let (store, database) = try makeStore()
        try await store.addWeekendActivity("Hike", asOf: now)
        try await store.addWeekendActivity("Movie night", asOf: now)
        try await store.removeWeekendActivity(at: 0, asOf: now)

        #expect(store.currentWeekendPlan(asOf: now)?.activities == ["Movie night"])

        let nextWeek = now.addingTimeInterval(7 * 86_400)
        #expect(store.currentWeekendPlan(asOf: nextWeek) == nil)

        let reloaded = RestStore(database: database)
        try await reloaded.load()
        #expect(reloaded.currentWeekendPlan(asOf: now)?.activities == ["Movie night"])
    }

    // MARK: - Agent tools

    @Test func logSleepToolCreatesEntryAndConfirms() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(
            id: "t1", name: "log_sleep", input: ["hours": 7.5, "recovery": "excellent"]
        )
        let result = await registry.execute(call)
        #expect(!result.isError)
        #expect(store.sleepEntries.count == 1)
        #expect(store.sleepEntries[0].recovery == .excellent)
        #expect(registry.confirmation(for: call) == "Logged 7.5h sleep")

        let bad = await registry.execute(
            LLMToolCall(id: "t2", name: "log_sleep", input: ["hours": 30])
        )
        #expect(bad.isError)
    }

    @Test func restSummaryToolIsSilentAndComplete() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        try await store.load()
        try await store.add(entry("s1", hours: 8, recovery: .excellent, daysAgo: 1, from: now))
        try await store.toggleDetox(on: now)
        try await store.logWorkHours(8, on: now)
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(id: "t1", name: "get_rest_summary", input: .object([:]))
        let result = await registry.execute(call)
        let json = JSONValue.decoded(from: result.content)

        #expect(json?["avgSleepHoursLast7"]?.doubleValue == 8)
        #expect(json?["recoveryLevel"]?.stringValue == "excellent")
        #expect(json?["schedule"]?["bedtime"]?.stringValue == "23:00")
        #expect(json?["detoxStreakDays"]?.intValue == 1)
        #expect(json?["weeklyWorkHours"]?.doubleValue == 8)
        #expect(json?["recentSleep"]?.arrayValue?.count == 1)
        #expect(registry.confirmation(for: call) == nil)
    }

    @Test func toolsAreScopedToRestSphere() throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)
        #expect(registry.toolsFor(.rest).map(\.name).sorted() == ["get_rest_summary", "log_sleep"])
        #expect(registry.toolsFor(.health).isEmpty)
    }
}

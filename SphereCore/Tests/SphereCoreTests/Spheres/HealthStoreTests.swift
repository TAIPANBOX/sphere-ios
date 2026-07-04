import Foundation
import Testing
@testable import SphereCore

struct FakeMetricsProvider: HealthMetricsProviding {
    var metrics = HealthMetrics(
        steps: 8_450, heartRate: 62, sleepHours: 7.34, calories: 512.6, hrv: 48.2,
        weeklySteps: [4_000, 9_000, 11_000, 7_000, 10_500, 6_000, 8_450]
    )

    func requestAuthorization() async -> Bool { true }
    func todayMetrics() async -> HealthMetrics { metrics }
}

@Suite("HealthStore")
@MainActor
struct HealthStoreTests {
    private func makeStore(
        engram: EngramStore? = nil,
        metrics: (any HealthMetricsProviding)? = nil
    ) throws -> (HealthStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (HealthStore(database: database, engram: engram, metricsProvider: metrics), database)
    }

    // MARK: - Water

    @Test func waterClampsAndPersistsPerDay() async throws {
        let (store, database) = try makeStore()
        try await store.load()

        try await store.removeWaterGlass()
        #expect(store.waterToday == 0)

        for _ in 0..<15 {
            try await store.addWaterGlass()
        }
        #expect(store.waterToday == HealthStore.maxWaterGlasses)

        let reloaded = HealthStore(database: database)
        try await reloaded.load()
        #expect(reloaded.waterToday == HealthStore.maxWaterGlasses)
    }

    @Test func incrementWaterAccumulatesInSQLAndCaps() async throws {
        let (store, database) = try makeStore()
        try await store.load()

        // Each increment is a self-contained atomic SQL statement (no
        // read-modify-write on waterToday), so counts accumulate exactly.
        for _ in 0..<5 { try await store.incrementWater() }
        #expect(store.waterToday == 5)

        // Persisted, not just in-memory.
        let reloaded = HealthStore(database: database)
        try await reloaded.load()
        #expect(reloaded.waterToday == 5)

        // Caps at the max.
        for _ in 0..<20 { try await store.incrementWater() }
        #expect(store.waterToday == HealthStore.maxWaterGlasses)
    }

    @Test func waterIsScopedToToday() async throws {
        let (store, database) = try makeStore()
        try await store.load()
        try await store.addWaterGlass()

        // Yesterday's bucket is separate: loading "as of tomorrow" sees zero.
        let tomorrow = Date().addingTimeInterval(86_400)
        let reloaded = HealthStore(database: database)
        try await reloaded.load(today: tomorrow)
        #expect(reloaded.waterToday == 0)
    }

    // MARK: - Weight

    @Test func logWeightOverwritesSameDayAndSorts() async throws {
        let (store, database) = try makeStore()
        try await store.load()

        try await store.logWeight(kg: 71.0, on: Date().addingTimeInterval(-86_400))
        try await store.logWeight(kg: 72.8)
        try await store.logWeight(kg: 72.4)

        #expect(store.weights.count == 2)
        #expect(store.latestWeight?.kg == 72.4)

        let reloaded = HealthStore(database: database)
        try await reloaded.load()
        #expect(reloaded.weights.map(\.kg) == [71.0, 72.4])
    }

    @Test func bmiComputesFromLatestWeight() async throws {
        let (store, _) = try makeStore()
        #expect(store.bmi(heightCm: 180) == nil)

        try await store.logWeight(kg: 72.0)
        let bmi = try #require(store.bmi(heightCm: 180))
        #expect(abs(bmi - 22.22) < 0.01)
        #expect(store.bmi(heightCm: 0) == nil)
    }

    @Test func weightLogNotesIntoEngram() async throws {
        let engram = try EngramStore.inMemory()
        let (store, _) = try makeStore(engram: engram)
        try await store.logWeight(kg: 72.45)

        var count = 0
        for _ in 0..<50 where count == 0 {
            count = try await engram.count(agentId: "health")
            if count == 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        let memories = try await engram.recall("weight", agentId: "health")
        #expect(memories.first?.content == "Logged weight 72.5 kg")
    }

    // MARK: - Workouts

    @Test func workoutsPersistSortAndCount() async throws {
        let (store, database) = try makeStore()
        let now = Date()
        try await store.addWorkout(Workout(
            id: "w1", type: .running, durationMinutes: 40, date: now.addingTimeInterval(-3_600)
        ))
        try await store.addWorkout(Workout(
            id: "w2", type: .yoga, durationMinutes: 20, date: now
        ))

        #expect(store.sortedWorkouts.map(\.id) == ["w2", "w1"])
        #expect(store.totalWorkoutMinutes == 60)

        try await store.removeWorkout(id: "w1")
        let reloaded = HealthStore(database: database)
        try await reloaded.load()
        #expect(reloaded.workouts.map(\.id) == ["w2"])
    }

    @Test func thisWeekCountUsesIsoWeek() async throws {
        let (store, _) = try makeStore()
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())!.start

        try await store.addWorkout(Workout(
            id: "in", type: .gym, durationMinutes: 30, date: weekStart.addingTimeInterval(3_600)
        ))
        try await store.addWorkout(Workout(
            id: "out", type: .gym, durationMinutes: 30, date: weekStart.addingTimeInterval(-3_600)
        ))
        #expect(store.thisWeekCount() == 1)
    }

    // MARK: - Metrics

    @Test func refreshMetricsPullsFromProvider() async throws {
        let (store, _) = try makeStore(metrics: FakeMetricsProvider())
        #expect(store.metrics == .empty)
        #expect(!store.metricsAvailable)

        await store.refreshMetrics()
        #expect(store.metrics.steps == 8_450)
        #expect(store.metricsAvailable)
        #expect(await store.requestHealthAccess())
    }

    @Test func refreshWithoutProviderKeepsEmptyMetrics() async throws {
        let (store, _) = try makeStore()
        await store.refreshMetrics()
        #expect(store.metrics == .empty)
        #expect(!store.metricsAvailable)
        #expect(!(await store.requestHealthAccess()))
    }

    // MARK: - Agent tools

    @Test func logWaterToolAddsGlassesAndConfirms() async throws {
        let (store, _) = try makeStore()
        try await store.load()
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(id: "t1", name: "log_water_glass", input: ["count": 3])
        let result = await registry.execute(call)

        #expect(!result.isError)
        #expect(store.waterToday == 3)
        #expect(JSONValue.decoded(from: result.content)?["total_today"]?.intValue == 3)
        #expect(registry.confirmation(for: call) == "Logged 3 glasses of water")
        #expect(
            registry.confirmation(for: LLMToolCall(id: "t2", name: "log_water_glass", input: .object([:])))
                == "Logged 1 glass of water"
        )
    }

    @Test func logWeightToolValidatesRange() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)

        let bad = await registry.execute(
            LLMToolCall(id: "t1", name: "log_weight", input: ["kg": 500])
        )
        #expect(bad.isError)
        #expect(store.weights.isEmpty)

        let good = await registry.execute(
            LLMToolCall(id: "t2", name: "log_weight", input: ["kg": 72.5])
        )
        #expect(!good.isError)
        #expect(store.latestWeight?.kg == 72.5)
    }

    @Test func healthSnapshotToolIsSilentAndComplete() async throws {
        let (store, _) = try makeStore(metrics: FakeMetricsProvider())
        try await store.load()
        await store.refreshMetrics()
        try await store.addWaterGlass()
        try await store.logWeight(kg: 72.5)
        try await store.addWorkout(Workout(id: "w1", type: .running, durationMinutes: 40, date: Date()))
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(id: "t1", name: "get_health_today", input: .object([:]))
        let result = await registry.execute(call)
        let json = JSONValue.decoded(from: result.content)

        #expect(json?["today"]?["steps"]?.intValue == 8_450)
        #expect(json?["today"]?["sleepHours"]?.doubleValue == 7.3)
        #expect(json?["waterGlassesToday"]?.intValue == 1)
        #expect(json?["latestWeightKg"]?.doubleValue == 72.5)
        #expect(json?["recentWorkouts"]?[0]?["type"]?.stringValue == "Running")
        #expect(registry.confirmation(for: call) == nil)
    }

    @Test func snapshotOmitsMetricsWhenUnavailable() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)
        let result = await registry.execute(
            LLMToolCall(id: "t1", name: "get_health_today", input: .object([:]))
        )
        let json = JSONValue.decoded(from: result.content)
        #expect(json?["today"] == nil)
        #expect(json?["waterGlassesToday"]?.intValue == 0)
    }

    @Test func toolsAreScopedToHealthSphere() throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)
        #expect(
            registry.toolsFor(.health).map(\.name).sorted()
                == ["get_health_today", "log_energy", "log_meal", "log_period",
                    "log_water_glass", "log_weight"]
        )
        #expect(registry.toolsFor(.finance).isEmpty)
    }

    // MARK: - Cycle

    @Test func logPeriodPersistsAndPredicts() async throws {
        let (store, database) = try makeStore()
        try await store.load()
        #expect(store.cyclePrediction() == nil)

        try await store.logPeriod(flow: .heavy)
        let prediction = try #require(store.cyclePrediction())
        #expect(prediction.currentCycleDay == 1)
        #expect(prediction.isEstimate)

        let reloaded = HealthStore(database: database)
        try await reloaded.load()
        #expect(reloaded.cycleEntries.count == 1)
        #expect(reloaded.cycleEntries.first?.flow == .heavy)
    }

    @Test func logPeriodSameDayOverwrites() async throws {
        let (store, _) = try makeStore()
        try await store.load()
        try await store.logPeriod(flow: .light)
        try await store.logPeriod(flow: .heavy, symptoms: [CycleSymptom.cramps.rawValue])
        #expect(store.cycleEntries.count == 1)
        #expect(store.cycleEntries.first?.flow == .heavy)
        #expect(store.cycleEntries.first?.symptoms == [CycleSymptom.cramps.rawValue])
    }

    @Test func logPeriodToolAndSnapshotSurfaceCycle() async throws {
        let (store, _) = try makeStore()
        try await store.load()
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(id: "t1", name: "log_period", input: ["flow": "medium"])
        let result = await registry.execute(call)
        #expect(!result.isError)
        #expect(store.cycleEntries.count == 1)
        #expect(registry.confirmation(for: call) == "Logged period start (medium flow)")

        let snapshot = await registry.execute(
            LLMToolCall(id: "t2", name: "get_health_today", input: .object([:]))
        )
        let json = JSONValue.decoded(from: snapshot.content)
        #expect(json?["cycle"]?["day"]?.intValue == 1)
        #expect(json?["cycle"]?["phase"]?.stringValue == "Menstrual")
    }
}

import Foundation
import Testing
@testable import SphereCore

/// Records write-back calls and serves fixed cycle flow, so both directions can
/// be verified without HealthKit.
private actor SpyHealthProvider: HealthMetricsProviding {
    var weights: [Double] = []
    var waterGlasses = 0
    var workouts: [(WorkoutType, Int)] = []
    var authRequested = false
    let cycleFlow: [CycleFlowDay]

    init(cycleFlow: [CycleFlowDay] = []) { self.cycleFlow = cycleFlow }

    func requestAuthorization() async -> Bool { authRequested = true; return true }
    func todayMetrics() async -> HealthMetrics { .empty }
    func recentCycleFlow(days: Int) async -> [CycleFlowDay] { cycleFlow }
    func writeWeight(kg: Double, date: Date) async { weights.append(kg) }
    func writeWaterGlass(date: Date) async { waterGlasses += 1 }
    func writeWorkout(type: WorkoutType, minutes: Int, calories: Int?, date: Date) async {
        workouts.append((type, minutes))
    }
}

@Suite("HealthStore write-back & cycle import")
@MainActor
struct HealthWriteBackTests {
    private let cal = Calendar(identifier: .gregorian)
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    private func makeStore(_ spy: SpyHealthProvider) throws -> HealthStore {
        let database = try AppDatabase.inMemory()
        return HealthStore(database: database, metricsProvider: spy)
    }

    @Test func loggingWeightWritesBack() async throws {
        let spy = SpyHealthProvider()
        let store = try makeStore(spy)
        try await store.logWeight(kg: 72.5)
        #expect(await spy.weights == [72.5])
    }

    @Test func incrementingWaterWritesBack() async throws {
        let spy = SpyHealthProvider()
        let store = try makeStore(spy)
        _ = try await store.incrementWater()
        _ = try await store.incrementWater()
        #expect(await spy.waterGlasses == 2)
    }

    @Test func addingWorkoutWritesBack() async throws {
        let spy = SpyHealthProvider()
        let store = try makeStore(spy)
        try await store.addWorkout(Workout(id: "w1", type: .running, durationMinutes: 30, date: Date()))
        let recorded = await spy.workouts
        #expect(recorded.count == 1)
        #expect(recorded.first?.0 == .running)
        #expect(recorded.first?.1 == 30)
    }

    @Test func importsCyclePeriodsFromHealth() async throws {
        let spy = SpyHealthProvider(cycleFlow: [
            CycleFlowDay(date: day(2026, 6, 1), flow: .medium),
            CycleFlowDay(date: day(2026, 6, 2), flow: .heavy),
            CycleFlowDay(date: day(2026, 6, 28), flow: .light),
        ])
        let store = try makeStore(spy)
        let count = await store.importCycleFromHealth()
        #expect(count == 2)
        #expect(store.cycleEntries.count == 2)
        #expect(await spy.authRequested)
    }

    @Test func cycleImportSkipsAlreadyLoggedStart() async throws {
        let spy = SpyHealthProvider(cycleFlow: [CycleFlowDay(date: day(2026, 6, 1), flow: .medium)])
        let store = try makeStore(spy)
        try await store.logPeriod(start: day(2026, 6, 1), flow: .heavy)
        let count = await store.importCycleFromHealth()
        #expect(count == 0)
        #expect(store.cycleEntries.count == 1)
        // Manual heavy entry preserved.
        #expect(store.cycleEntries.first?.flow == .heavy)
    }
}

import Foundation
import Testing
@testable import SphereCore

/// Feeds fixed nights so the import path is deterministic without HealthKit.
private struct FakeSleepProvider: HealthMetricsProviding {
    let nights: [SleepNight]
    func requestAuthorization() async -> Bool { true }
    func todayMetrics() async -> HealthMetrics { .empty }
    func recentSleepNights(days: Int) async -> [SleepNight] { nights }
}

@Suite("RestStore sleep import")
@MainActor
struct SleepImportStoreTests {
    private let cal = Calendar(identifier: .gregorian)
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 8))!
    }

    private func makeStore(_ nights: [SleepNight]) throws -> RestStore {
        let database = try AppDatabase.inMemory()
        return RestStore(database: database, metricsProvider: FakeSleepProvider(nights: nights))
    }

    @Test func importsNewNights() async throws {
        let store = try makeStore([
            SleepNight(date: day(2026, 6, 7), hours: 7.5),
            SleepNight(date: day(2026, 6, 8), hours: 6.2),
        ])
        let count = await store.importSleepFromHealth()
        #expect(count == 2)
        #expect(store.sleepEntries.count == 2)
        // Newest first, rounded to 0.1h.
        #expect(store.sleepEntries.first?.hoursSlept == 6.2)
        #expect(store.sleepEntries.first?.note == "From Apple Health")
    }

    @Test func doesNotOverwriteManuallyLoggedNight() async throws {
        let store = try makeStore([SleepNight(date: day(2026, 6, 8), hours: 6.0)])
        try await store.add(SleepEntry(id: "manual", date: day(2026, 6, 8), hoursSlept: 9))
        let count = await store.importSleepFromHealth()
        #expect(count == 0)
        #expect(store.sleepEntries.count == 1)
        #expect(store.sleepEntries.first?.hoursSlept == 9)
    }

    @Test func reimportIsIdempotent() async throws {
        let store = try makeStore([SleepNight(date: day(2026, 6, 8), hours: 7)])
        _ = await store.importSleepFromHealth()
        let second = await store.importSleepFromHealth()
        #expect(second == 0)
        #expect(store.sleepEntries.count == 1)
    }

    @Test func skipsNegligibleNights() async throws {
        let store = try makeStore([SleepNight(date: day(2026, 6, 8), hours: 0.2)])
        let count = await store.importSleepFromHealth()
        #expect(count == 0)
    }

    @Test func noProviderImportsNothing() async throws {
        let database = try AppDatabase.inMemory()
        let store = RestStore(database: database)
        #expect(store.hasHealthProvider == false)
        #expect(await store.importSleepFromHealth() == 0)
    }
}

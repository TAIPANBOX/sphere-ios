#if canImport(HealthKit)
import Foundation
import HealthKit

/// Live HealthKit-backed metrics provider. Read-only; mirrors what the
/// Flutter `health` package pulled: today's steps/calories, latest heart
/// rate (last hour), last night's in-bed sleep, latest HRV (24 h), and the
/// 7-day steps series.
///
/// `@unchecked Sendable`: HKHealthStore is documented thread-safe and the
/// class holds no other mutable state.
public final class HealthKitService: HealthMetricsProviding, @unchecked Sendable {
    private let store = HKHealthStore()

    public init() {}

    private static var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.sleepAnalysis),
        ]
    }

    public func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
            return true
        } catch {
            return false
        }
    }

    public func todayMetrics() async -> HealthMetrics {
        guard HKHealthStore.isHealthDataAvailable() else { return .empty }

        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = todayStart.addingTimeInterval(-86_400)

        async let steps = sum(.stepCount, from: todayStart, to: now, unit: .count())
        async let heartRate = latest(
            .heartRate, from: now.addingTimeInterval(-3_600), to: now,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let calories = sum(.activeEnergyBurned, from: todayStart, to: now, unit: .kilocalorie())
        async let hrv = latest(
            .heartRateVariabilitySDNN, from: yesterdayStart, to: now,
            unit: .secondUnit(with: .milli)
        )
        async let sleep = inBedHours(from: yesterdayStart, to: todayStart)
        async let weekly = weeklySteps(now: now, calendar: calendar)

        return HealthMetrics(
            steps: Int(await steps),
            heartRate: await heartRate ?? 0,
            sleepHours: await sleep,
            calories: (await calories).rounded(),
            hrv: await hrv ?? 0,
            weeklySteps: await weekly
        )
    }

    // MARK: - Queries

    private func weeklySteps(now: Date, calendar: Calendar) async -> [Int] {
        var results: [Int] = []
        for daysAgo in stride(from: 6, through: 0, by: -1) {
            let day = calendar.startOfDay(for: now.addingTimeInterval(Double(-daysAgo) * 86_400))
            let next = day.addingTimeInterval(86_400)
            results.append(Int(await sum(.stepCount, from: day, to: next, unit: .count())))
        }
        return results
    }

    private func sum(
        _ identifier: HKQuantityTypeIdentifier,
        from start: Date,
        to end: Date,
        unit: HKUnit
    ) async -> Double {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(identifier),
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: .cumulativeSum
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    private func latest(
        _ identifier: HKQuantityTypeIdentifier,
        from start: Date,
        to end: Date,
        unit: HKUnit
    ) async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(identifier),
                predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func inBedHours(from start: Date, to end: Date) async -> Double {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let seconds = (samples as? [HKCategorySample] ?? [])
                    .filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: seconds / 3_600)
            }
            store.execute(query)
        }
    }
}
#endif

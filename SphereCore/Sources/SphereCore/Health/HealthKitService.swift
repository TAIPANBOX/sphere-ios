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
public final class HealthKitService: HealthMetricsProviding, MindfulSessionWriting, @unchecked Sendable {
    private let store = HKHealthStore()

    public init() {}

    private static var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.bodyMass),
            HKCategoryType(.sleepAnalysis),
            HKCategoryType(.menstrualFlow),
            HKObjectType.workoutType(),
        ]
    }

    private static var shareTypes: Set<HKSampleType> {
        [
            HKQuantityType(.bodyMass),
            HKQuantityType(.dietaryWater),
            HKQuantityType(.activeEnergyBurned),
            HKObjectType.workoutType(),
            HKCategoryType(.mindfulSession),
        ]
    }

    public func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Write-back

    public func writeWeight(kg: Double, date: Date) async {
        await save(.bodyMass, value: kg, unit: .gramUnit(with: .kilo), date: date)
    }

    public func writeWaterGlass(date: Date) async {
        // A glass ≈ 250 ml.
        await save(.dietaryWater, value: 0.25, unit: .liter(), date: date)
    }

    public func writeWorkout(type: WorkoutType, minutes: Int, calories: Int?, date: Date) async {
        guard HKHealthStore.isHealthDataAvailable(), minutes > 0 else { return }
        let end = date
        let start = end.addingTimeInterval(Double(-minutes) * 60)
        let config = HKWorkoutConfiguration()
        config.activityType = Self.activityType(for: type)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: nil)
        do {
            try await builder.beginCollection(at: start)
            if let calories, calories > 0 {
                let energy = HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double(calories)),
                    start: start, end: end
                )
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    builder.add([energy]) { _, error in
                        if let error { cont.resume(throwing: error) } else { cont.resume() }
                    }
                }
            }
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            // Write-back is best-effort; a failed sample must not break logging.
        }
    }

    public func writeMindfulSession(start: Date, end: Date) async {
        guard HKHealthStore.isHealthDataAvailable(), end > start else { return }
        let sample = HKCategorySample(
            type: HKCategoryType(.mindfulSession),
            value: HKCategoryValue.notApplicable.rawValue,
            start: start, end: end
        )
        try? await store.save(sample)
    }

    private func save(
        _ identifier: HKQuantityTypeIdentifier, value: Double, unit: HKUnit, date: Date
    ) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let sample = HKQuantitySample(
            type: HKQuantityType(identifier),
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: date, end: date
        )
        try? await store.save(sample)
    }

    private static func activityType(for type: WorkoutType) -> HKWorkoutActivityType {
        switch type {
        case .running: .running
        case .cycling: .cycling
        case .swimming: .swimming
        case .gym: .traditionalStrengthTraining
        case .yoga: .yoga
        case .walking: .walking
        case .hiit: .highIntensityIntervalTraining
        case .other: .other
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

    public func recentSleepNights(days: Int) async -> [SleepNight] {
        guard HKHealthStore.isHealthDataAvailable(), days > 0 else { return [] }
        let end = Date()
        let start = Calendar.current.startOfDay(for: end)
            .addingTimeInterval(Double(-days) * 86_400)
        let intervals = await sleepIntervals(from: start, to: end)
        return SleepImport.nights(from: intervals)
    }

    public func recentCycleFlow(days: Int) async -> [CycleFlowDay] {
        guard HKHealthStore.isHealthDataAvailable(), days > 0 else { return [] }
        let end = Date()
        let start = Calendar.current.startOfDay(for: end)
            .addingTimeInterval(Double(-days) * 86_400)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.menstrualFlow),
                predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let days = (samples as? [HKCategorySample] ?? []).compactMap { sample -> CycleFlowDay? in
                    guard let flow = Self.flowLevel(sample.value) else { return nil }
                    return CycleFlowDay(date: sample.startDate, flow: flow)
                }
                continuation.resume(returning: days)
            }
            store.execute(query)
        }
    }

    private static func flowLevel(_ value: Int) -> FlowLevel? {
        switch value {
        case HKCategoryValueMenstrualFlow.light.rawValue: return .light
        case HKCategoryValueMenstrualFlow.medium.rawValue: return .medium
        case HKCategoryValueMenstrualFlow.heavy.rawValue: return .heavy
        case HKCategoryValueMenstrualFlow.unspecified.rawValue: return .medium
        default: return nil  // .none = no bleeding
        }
    }

    private func sleepIntervals(from start: Date, to end: Date) async -> [SleepInterval] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let intervals = (samples as? [HKCategorySample] ?? []).map { sample in
                    SleepInterval(
                        start: sample.startDate, end: sample.endDate,
                        asleep: Self.isAsleep(sample.value)
                    )
                }
                continuation.resume(returning: intervals)
            }
            store.execute(query)
        }
    }

    /// True for real sleep stages; false for `inBed` (awake in bed) and `awake`.
    private static func isAsleep(_ value: Int) -> Bool {
        switch value {
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
             HKCategoryValueSleepAnalysis.asleepCore.rawValue,
             HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
             HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return true
        default:
            return false
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

    // MARK: - Workout & weight history import

    /// Workouts logged in Health over the trailing `days`, excluding samples
    /// this app itself wrote (we already write workouts TO HealthKit via
    /// `writeWorkout`, so re-reading our own samples would duplicate them on
    /// import). Excluded via a predicate over `HKSource.default()` (this app).
    public func recentWorkouts(days: Int) async -> [HealthWorkoutSample] {
        guard HKHealthStore.isHealthDataAvailable(), days > 0 else { return [] }
        let end = Date()
        let start = Calendar.current.startOfDay(for: end).addingTimeInterval(Double(-days) * 86_400)
        let notOurs = NSCompoundPredicate(notPredicateWithSubpredicate:
            HKQuery.predicateForObjects(from: HKSource.default())
        )
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end), notOurs,
        ])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let workouts = (samples as? [HKWorkout] ?? []).map { workout -> HealthWorkoutSample in
                    let energy: Double? = workout
                        .statistics(for: HKQuantityType(.activeEnergyBurned))?
                        .sumQuantity()?
                        .doubleValue(for: .kilocalorie())
                    return HealthWorkoutSample(
                        date: workout.startDate,
                        durationMinutes: Int((workout.duration / 60).rounded()),
                        type: Self.workoutType(for: workout.workoutActivityType),
                        calories: energy.map { Int($0.rounded()) }
                    )
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    /// Body-mass entries logged in Health over the trailing `days`, excluding
    /// samples this app wrote (see `recentWorkouts`).
    public func weightHistory(days: Int) async -> [HealthWeightSample] {
        guard HKHealthStore.isHealthDataAvailable(), days > 0 else { return [] }
        let end = Date()
        let start = Calendar.current.startOfDay(for: end).addingTimeInterval(Double(-days) * 86_400)
        let notOurs = NSCompoundPredicate(notPredicateWithSubpredicate:
            HKQuery.predicateForObjects(from: HKSource.default())
        )
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end), notOurs,
        ])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.bodyMass),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let weights = (samples as? [HKQuantitySample] ?? []).map { sample in
                    HealthWeightSample(
                        date: sample.startDate,
                        kg: sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    )
                }
                continuation.resume(returning: weights)
            }
            store.execute(query)
        }
    }

    /// Maps HealthKit's workout taxonomy onto our smaller `WorkoutType` enum;
    /// anything not explicitly listed falls back to `.other`.
    private static func workoutType(for activity: HKWorkoutActivityType) -> WorkoutType {
        switch activity {
        case .running: .running
        case .cycling: .cycling
        case .swimming: .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining,
             .coreTraining, .mixedCardio:
            .gym
        case .yoga, .pilates, .flexibility, .mindAndBody: .yoga
        case .walking, .hiking: .walking
        case .highIntensityIntervalTraining: .hiit
        default: .other
        }
    }
}
#endif

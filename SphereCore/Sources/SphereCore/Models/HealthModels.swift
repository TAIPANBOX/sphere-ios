import Foundation
import GRDB

public struct HealthMetrics: Sendable, Equatable {
    public var steps: Int
    public var heartRate: Double
    public var sleepHours: Double
    public var calories: Double
    public var hrv: Double
    /// Last 7 days, oldest first, today last.
    public var weeklySteps: [Int]

    public init(
        steps: Int,
        heartRate: Double,
        sleepHours: Double,
        calories: Double,
        hrv: Double,
        weeklySteps: [Int]
    ) {
        self.steps = steps
        self.heartRate = heartRate
        self.sleepHours = sleepHours
        self.calories = calories
        self.hrv = hrv
        self.weeklySteps = weeklySteps
    }

    public static let empty = HealthMetrics(
        steps: 0, heartRate: 0, sleepHours: 0, calories: 0, hrv: 0,
        weeklySteps: [0, 0, 0, 0, 0, 0, 0]
    )
}

/// Live health-data source (HealthKit on device, a fake in tests/previews).
public protocol HealthMetricsProviding: Sendable {
    func requestAuthorization() async -> Bool
    func todayMetrics() async -> HealthMetrics
    /// Per-night sleep for the trailing `days`, newest last. Default returns
    /// nothing so providers without sleep access (and test stubs) still compile.
    func recentSleepNights(days: Int) async -> [SleepNight]
    /// Per-day menstrual flow for the trailing `days`.
    func recentCycleFlow(days: Int) async -> [CycleFlowDay]
    /// Workouts logged in Health over the trailing `days` (excludes samples
    /// this app itself wrote — see `HealthKitService.recentWorkouts`).
    func recentWorkouts(days: Int) async -> [HealthWorkoutSample]
    /// Body-mass entries logged in Health over the trailing `days` (excludes
    /// samples this app itself wrote).
    func weightHistory(days: Int) async -> [HealthWeightSample]
    /// Write-back: mirror a Sphere log into Apple Health (no-op when unavailable).
    func writeWeight(kg: Double, date: Date) async
    func writeWaterGlass(date: Date) async
    func writeWorkout(type: WorkoutType, minutes: Int, calories: Int?, date: Date) async
}

public extension HealthMetricsProviding {
    func recentSleepNights(days: Int) async -> [SleepNight] { [] }
    func recentCycleFlow(days: Int) async -> [CycleFlowDay] { [] }
    func recentWorkouts(days: Int) async -> [HealthWorkoutSample] { [] }
    func weightHistory(days: Int) async -> [HealthWeightSample] { [] }
    func writeWeight(kg: Double, date: Date) async {}
    func writeWaterGlass(date: Date) async {}
    func writeWorkout(type: WorkoutType, minutes: Int, calories: Int?, date: Date) async {}
}

/// One workout read back from a health source, flattened so the import logic
/// stays HealthKit-free and testable.
public struct HealthWorkoutSample: Sendable, Equatable {
    public let date: Date
    public let durationMinutes: Int
    public let type: WorkoutType
    public let calories: Int?

    public init(date: Date, durationMinutes: Int, type: WorkoutType, calories: Int? = nil) {
        self.date = date
        self.durationMinutes = durationMinutes
        self.type = type
        self.calories = calories
    }
}

/// One body-mass reading read back from a health source.
public struct HealthWeightSample: Sendable, Equatable {
    public let date: Date
    public let kg: Double

    public init(date: Date, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

/// Write-back seam for the Mindfulness sphere (HealthKit `mindfulSession` on
/// device, a fake in tests). Kept separate from `HealthMetricsProviding`
/// since a mindful-session writer has no read/metrics surface of its own.
public protocol MindfulSessionWriting: Sendable {
    func writeMindfulSession(start: Date, end: Date) async
}

public enum WorkoutType: String, Codable, CaseIterable, Sendable {
    case running, cycling, swimming, gym, yoga, walking, hiit, other

    public var label: String {
        switch self {
        case .running: "Running"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .gym: "Gym"
        case .yoga: "Yoga"
        case .walking: "Walking"
        case .hiit: "HIIT"
        case .other: "Other"
        }
    }

    public var emoji: String {
        switch self {
        case .running: "🏃"
        case .cycling: "🚴"
        case .swimming: "🏊"
        case .gym: "🏋️"
        case .yoga: "🧘"
        case .walking: "🚶"
        case .hiit: "⚡"
        case .other: "💪"
        }
    }
}

public struct Workout: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var type: WorkoutType
    public var durationMinutes: Int
    public var caloriesBurned: Int?
    public var distanceKm: Double?
    public var date: Date
    public var note: String

    public init(
        id: String,
        type: WorkoutType = .other,
        durationMinutes: Int,
        caloriesBurned: Int? = nil,
        distanceKm: Double? = nil,
        date: Date,
        note: String = ""
    ) {
        self.id = id
        self.type = type
        self.durationMinutes = durationMinutes
        self.caloriesBurned = caloriesBurned
        self.distanceKm = distanceKm
        self.date = date
        self.note = note
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("workout", now: now)
    }
}

extension Workout: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "workouts"
}

/// One weight measurement per calendar day; logging again overwrites.
public struct WeightEntry: Codable, Equatable, Sendable {
    public var dateKey: String
    public var date: Date
    public var kg: Double

    public init(date: Date, kg: Double) {
        self.dateKey = DayKey.make(date)
        self.date = date
        self.kg = kg
    }
}

extension WeightEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "weights"
}

public enum MedFrequency: String, Codable, CaseIterable, Sendable {
    case once, twice, threePerDay

    public var label: String {
        switch self {
        case .once: "Once daily"
        case .twice: "Twice daily"
        case .threePerDay: "3× daily"
        }
    }
}

public struct Medication: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var dosage: String
    public var frequency: MedFrequency
    /// Day keys ("yyyy-MM-dd") the dose was marked taken.
    public var takenDates: [String]

    public init(
        id: String,
        name: String,
        dosage: String = "",
        frequency: MedFrequency = .once,
        takenDates: [String] = []
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.frequency = frequency
        self.takenDates = takenDates
    }

    public func takenToday(on date: Date = Date()) -> Bool {
        takenDates.contains(DayKey.make(date))
    }

    public func markingTaken(on date: Date = Date()) -> Medication {
        let key = DayKey.make(date)
        guard !takenDates.contains(key) else { return self }
        var copy = self
        copy.takenDates.append(key)
        return copy
    }

    public func unmarkingTaken(on date: Date = Date()) -> Medication {
        let key = DayKey.make(date)
        var copy = self
        copy.takenDates.removeAll { $0 == key }
        return copy
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("med_rx", now: now)
    }
}

extension Medication: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "medications"
}

public struct LabResult: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var value: String
    public var unit: String
    public var refRange: String
    public var date: Date
    public var isNormal: Bool

    public init(
        id: String,
        name: String,
        value: String,
        unit: String = "",
        refRange: String = "",
        date: Date,
        isNormal: Bool = true
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.unit = unit
        self.refRange = refRange
        self.date = date
        self.isNormal = isNormal
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("lab", now: now)
    }
}

extension LabResult: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "lab_results"
}

/// "yyyy-MM-dd" bucket keys — water intake, weight overwrites, habit
/// check-ins, tool payload dates.
///
/// Pinned to the Gregorian calendar (in the user's time zone) so keys stay
/// stable when the device uses a Buddhist/Japanese locale calendar and match
/// the Dart data, which was always Gregorian.
public enum DayKey {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    public static func make(_ date: Date = Date()) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Parses a "yyyy-MM-dd" key back to the start of that day.
    public static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Shifts a day key by `days` (negative = earlier).
    public static func shift(_ key: String, byDays days: Int) -> String? {
        guard let date = date(from: key),
              let shifted = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return make(shifted)
    }
}

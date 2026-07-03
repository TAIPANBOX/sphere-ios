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
        "workout_\(Int64(now.timeIntervalSince1970 * 1000))"
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

/// "yyyy-MM-dd" bucket keys in the user's current calendar — water intake,
/// weight overwrites, habit check-ins.
public enum DayKey {
    public static func make(_ date: Date = Date()) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

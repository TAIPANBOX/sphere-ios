import Foundation
import GRDB
import Observation

/// Health sphere store: live HealthKit metrics (via an injected provider),
/// day-keyed water intake, weight log with BMI, and workouts.
/// Follows the golden-template shape — see docs/HANDOFF.md.
@MainActor
@Observable
public final class HealthStore {
    public private(set) var metrics: HealthMetrics = .empty
    public private(set) var metricsAvailable = false
    public private(set) var waterToday = 0
    public private(set) var weights: [WeightEntry] = []
    public private(set) var workouts: [Workout] = []
    public private(set) var medications: [Medication] = []
    public private(set) var labResults: [LabResult] = []

    public nonisolated static let waterGoalGlasses = 8
    public nonisolated static let maxWaterGlasses = 12
    public nonisolated static let stepsGoal = 10_000

    private let database: AppDatabase
    private let engram: EngramStore?
    private let metricsProvider: (any HealthMetricsProviding)?

    public init(
        database: AppDatabase,
        engram: EngramStore? = nil,
        metricsProvider: (any HealthMetricsProviding)? = nil
    ) {
        self.database = database
        self.engram = engram
        self.metricsProvider = metricsProvider
    }

    public func load(today: Date = Date()) async throws {
        let todayKey = DayKey.make(today)
        let (water, weights, workouts, medications, labs) = try await database.writer.read { db in
            (
                try Int.fetchOne(
                    db, sql: "SELECT glasses FROM water WHERE dateKey = ?", arguments: [todayKey]
                ) ?? 0,
                try WeightEntry.fetchAll(db, sql: "SELECT * FROM weights ORDER BY date"),
                try Workout.fetchAll(db),
                try Medication.fetchAll(db),
                try LabResult.fetchAll(db, sql: "SELECT * FROM lab_results ORDER BY date DESC")
            )
        }
        self.waterToday = water
        self.weights = weights
        self.workouts = workouts
        self.medications = medications
        self.labResults = labs
    }

    /// Pulls fresh metrics from HealthKit (or whatever provider is wired).
    public func refreshMetrics() async {
        guard let metricsProvider else { return }
        metrics = await metricsProvider.todayMetrics()
        metricsAvailable = true
    }

    public func requestHealthAccess() async -> Bool {
        guard let metricsProvider else { return false }
        return await metricsProvider.requestAuthorization()
    }

    // MARK: - Water

    public func addWaterGlass(on date: Date = Date()) async throws {
        try await setWater(waterToday + 1, on: date)
    }

    public func removeWaterGlass(on date: Date = Date()) async throws {
        try await setWater(waterToday - 1, on: date)
    }

    private func setWater(_ glasses: Int, on date: Date) async throws {
        let clamped = min(max(glasses, 0), Self.maxWaterGlasses)
        let key = DayKey.make(date)
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO water (dateKey, glasses) VALUES (?, ?)
                    ON CONFLICT(dateKey) DO UPDATE SET glasses = excluded.glasses
                    """,
                arguments: [key, clamped]
            )
        }
        waterToday = clamped
    }

    /// Adds one glass atomically in SQL (capped), returning the new count.
    /// Used by the watch quick-log path so two near-simultaneous commands
    /// can't lose an increment via a read-modify-write on `waterToday`.
    @discardableResult
    public func incrementWater(on date: Date = Date()) async throws -> Int {
        let key = DayKey.make(date)
        let cap = Self.maxWaterGlasses
        let newValue = try await database.writer.write { db -> Int in
            try db.execute(
                sql: """
                    INSERT INTO water (dateKey, glasses) VALUES (?, 1)
                    ON CONFLICT(dateKey) DO UPDATE SET glasses = MIN(glasses + 1, ?)
                    """,
                arguments: [key, cap]
            )
            return try Int.fetchOne(
                db, sql: "SELECT glasses FROM water WHERE dateKey = ?", arguments: [key]
            ) ?? 0
        }
        if key == DayKey.make() { waterToday = newValue }
        return newValue
    }

    // MARK: - Weight

    /// Records today's weight, overwriting an earlier entry for the same day.
    public func logWeight(kg: Double, on date: Date = Date()) async throws {
        let entry = WeightEntry(date: date, kg: kg)
        try await database.writer.write { db in try entry.save(db) }
        weights.removeAll { $0.dateKey == entry.dateKey }
        weights.append(entry)
        weights.sort { $0.date < $1.date }
        engram?.note(
            agentId: SphereType.health.rawValue,
            content: "Logged weight \(String(format: "%.1f", kg)) kg",
            tags: ["log", "health", "weight"]
        )
    }

    public var latestWeight: WeightEntry? {
        weights.last
    }

    public func bmi(heightCm: Double) -> Double? {
        guard let latestWeight, heightCm > 0 else { return nil }
        let meters = heightCm / 100
        return latestWeight.kg / (meters * meters)
    }

    // MARK: - Workouts

    public func addWorkout(_ workout: Workout) async throws {
        try await database.writer.write { db in try workout.insert(db) }
        workouts.append(workout)
        engram?.note(
            agentId: SphereType.health.rawValue,
            content: "Logged \(workout.type.label) workout, \(workout.durationMinutes) min",
            tags: ["log", "health", "workout"]
        )
    }

    public func removeWorkout(id: String) async throws {
        _ = try await database.writer.write { db in try Workout.deleteOne(db, key: id) }
        workouts.removeAll { $0.id == id }
    }

    public var sortedWorkouts: [Workout] {
        workouts.sorted { $0.date > $1.date }
    }

    /// Workouts since Monday of the current ISO week.
    public func thisWeekCount(asOf now: Date = Date()) -> Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return workouts.count { $0.date >= week.start }
    }

    public var totalWorkoutMinutes: Int {
        workouts.reduce(0) { $0 + $1.durationMinutes }
    }

    // MARK: - Medications

    public func addMedication(_ medication: Medication) async throws {
        try await database.writer.write { db in try medication.insert(db) }
        medications.append(medication)
        engram?.note(
            agentId: SphereType.health.rawValue,
            content: "Started medication: \(medication.name)"
                + (medication.dosage.isEmpty ? "" : " (\(medication.dosage))"),
            tags: ["log", "health", "medication"]
        )
    }

    public func removeMedication(id: String) async throws {
        _ = try await database.writer.write { db in try Medication.deleteOne(db, key: id) }
        medications.removeAll { $0.id == id }
    }

    public func toggleMedication(id: String, on date: Date = Date()) async throws {
        guard let medication = medications.first(where: { $0.id == id }) else { return }
        let toggled = medication.takenToday(on: date)
            ? medication.unmarkingTaken(on: date)
            : medication.markingTaken(on: date)
        try await database.writer.write { db in try toggled.save(db) }
        medications = medications.map { $0.id == id ? toggled : $0 }
    }

    public func medicationsTakenToday(on date: Date = Date()) -> Int {
        medications.count { $0.takenToday(on: date) }
    }

    // MARK: - Lab results

    public func addLabResult(_ result: LabResult) async throws {
        try await database.writer.write { db in try result.insert(db) }
        labResults.insert(result, at: 0)
    }

    public func removeLabResult(id: String) async throws {
        _ = try await database.writer.write { db in try LabResult.deleteOne(db, key: id) }
        labResults.removeAll { $0.id == id }
    }

    // MARK: - Agent tools

    public nonisolated var tools: [SphereTool] {
        [
            SphereTool(
                definition: LLMTool(
                    name: "log_water_glass",
                    description: "Record that the user drank water. count is the number of "
                        + "glasses (default 1). Use when the user mentions drinking water.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "count": [
                                "type": "integer", "minimum": 1, "maximum": 12,
                                "description": "Glasses drunk",
                            ],
                        ],
                        "required": [],
                    ]
                ),
                spheres: [.health],
                confirmation: { input in
                    let count = input["count"]?.intValue ?? 1
                    return count == 1
                        ? "Logged 1 glass of water"
                        : "Logged \(count) glasses of water"
                },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    let count = input["count"]?.intValue ?? 1
                    for _ in 0..<count {
                        try await self.addWaterGlass()
                    }
                    let total = await self.waterToday
                    return JSONValue.object([
                        "ok": true, "total_today": .number(Double(total)),
                    ]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "log_weight",
                    description: "Record the user's body weight in kilograms. Overwrites "
                        + "today's entry if one already exists.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "kg": [
                                "type": "number", "minimum": 20, "maximum": 400,
                                "description": "Weight in kg",
                            ],
                        ],
                        "required": ["kg"],
                    ]
                ),
                spheres: [.health],
                confirmation: { input in
                    "Logged weight \(input["kg"]?.doubleValue.map { String(format: "%g", $0) } ?? "?") kg"
                },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let kg = input["kg"]?.doubleValue, (20...400).contains(kg) else {
                        throw AgentToolInputError("kg is required (20–400)")
                    }
                    try await self.logWeight(kg: kg)
                    return JSONValue.object(["ok": true, "kg": .number(kg)]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "get_health_today",
                    description: "Look up the user's health snapshot: today's metrics (steps, "
                        + "sleep, resting heart rate, calories, HRV), water glasses, latest "
                        + "weight, and recent workouts.",
                    inputSchema: ["type": "object", "properties": [:], "required": []]
                ),
                spheres: [.health],
                silent: true,
                handler: { [weak self] _ in
                    guard let self else { throw CancellationError() }
                    return await self.healthSnapshotJSON()
                }
            ),
        ]
    }

    private func healthSnapshotJSON() -> String {
        var snapshot: [String: JSONValue] = [
            "waterGlassesToday": .number(Double(waterToday)),
            "recentWorkouts": .array(sortedWorkouts.prefix(5).map { workout in
                .object([
                    "type": .string(workout.type.label),
                    "minutes": .number(Double(workout.durationMinutes)),
                    "date": .string(DayKey.make(workout.date)),
                ])
            }),
        ]
        if metricsAvailable {
            snapshot["today"] = .object([
                "steps": .number(Double(metrics.steps)),
                "sleepHours": .number((metrics.sleepHours * 10).rounded() / 10),
                "restingHeartRate": .number(metrics.heartRate.rounded()),
                "caloriesBurned": .number(metrics.calories.rounded()),
                "hrv": .number(metrics.hrv.rounded()),
            ])
        }
        if let latestWeight {
            snapshot["latestWeightKg"] = .number(latestWeight.kg)
        }
        if !medications.isEmpty {
            snapshot["medications"] = .object([
                "total": .number(Double(medications.count)),
                "takenToday": .number(Double(medicationsTakenToday())),
                "names": .array(medications.map { .string($0.name) }),
            ])
        }
        return JSONValue.object(snapshot).encodedString()
    }
}

import Foundation
import GRDB
import Observation

/// Persists whether the user has been through the "Connect Apple Health"
/// first-run flow. HealthKit deliberately hides read-authorization status, so
/// this app-side flag is the only way to know whether to prompt again. The
/// app wires a UserDefaults-backed implementation; tests and previews use
/// ``InMemoryHealthConnectPreferences``.
public protocol HealthConnectPreferences: Sendable {
    func hasCompletedHealthConnect() -> Bool
    func setCompletedHealthConnect(_ completed: Bool)
}

public final class InMemoryHealthConnectPreferences: HealthConnectPreferences, @unchecked Sendable {
    private let lock = NSLock()
    private var completed: Bool

    public init(completed: Bool = false) {
        self.completed = completed
    }

    public func hasCompletedHealthConnect() -> Bool {
        lock.withLock { completed }
    }

    public func setCompletedHealthConnect(_ completed: Bool) {
        lock.withLock { self.completed = completed }
    }
}

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
    public private(set) var cycleEntries: [CycleEntry] = []
    public private(set) var energyLevels: [String: Int] = [:]
    public private(set) var mealQuality: [String: Int] = [:]

    public nonisolated static let waterGoalGlasses = 8
    public nonisolated static let maxWaterGlasses = 12
    public nonisolated static let stepsGoal = 10_000

    private let database: AppDatabase
    private let engram: EngramStore?
    private let metricsProvider: (any HealthMetricsProviding)?
    private let connectPreferences: any HealthConnectPreferences

    public init(
        database: AppDatabase,
        engram: EngramStore? = nil,
        metricsProvider: (any HealthMetricsProviding)? = nil,
        connectPreferences: any HealthConnectPreferences = InMemoryHealthConnectPreferences()
    ) {
        self.database = database
        self.engram = engram
        self.metricsProvider = metricsProvider
        self.connectPreferences = connectPreferences
    }

    public func load(today: Date = Date()) async throws {
        let todayKey = DayKey.make(today)
        let (water, weights, workouts, medications, labs, cycles, energy, meals) =
            try await database.writer.read { db in
                (
                    try Int.fetchOne(
                        db, sql: "SELECT glasses FROM water WHERE dateKey = ?", arguments: [todayKey]
                    ) ?? 0,
                    try WeightEntry.fetchAll(db, sql: "SELECT * FROM weights ORDER BY date"),
                    try Workout.fetchAll(db),
                    try Medication.fetchAll(db),
                    try LabResult.fetchAll(db, sql: "SELECT * FROM lab_results ORDER BY date DESC"),
                    try CycleEntry.fetchAll(db, sql: "SELECT * FROM cycle_entries ORDER BY startDate DESC"),
                    try Row.fetchAll(db, sql: "SELECT dateKey, level FROM energy_levels")
                        .map { ($0["dateKey"] as String, $0["level"] as Int) },
                    try Row.fetchAll(db, sql: "SELECT dateKey, quality FROM meal_quality")
                        .map { ($0["dateKey"] as String, $0["quality"] as Int) }
                )
            }
        self.waterToday = water
        self.weights = weights
        self.workouts = workouts
        self.medications = medications
        self.labResults = labs
        self.cycleEntries = cycles
        self.energyLevels = Dictionary(uniqueKeysWithValues: energy)
        self.mealQuality = Dictionary(uniqueKeysWithValues: meals)
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

    /// Whether the first-run "Connect Apple Health" card should show: a
    /// provider is wired (so there's something to connect to) and the user
    /// hasn't been through the flow yet. HealthKit hides read-authorization
    /// status, so this is tracked app-side rather than derived from it.
    public var needsHealthConnect: Bool {
        hasHealthProvider && !connectPreferences.hasCompletedHealthConnect()
    }

    /// Marks the connect flow as done regardless of the outcome — the user
    /// may have denied some data types, but re-showing the card every launch
    /// would be worse than a metric silently reading "—".
    public func markHealthConnectCompleted() {
        connectPreferences.setCompletedHealthConnect(true)
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
        let newValue = try await QuickLogSQL.incrementWater(
            database.writer, cap: Self.maxWaterGlasses, on: date
        )
        if DayKey.make(date) == DayKey.make() { waterToday = newValue }
        await metricsProvider?.writeWaterGlass(date: date)
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
        await metricsProvider?.writeWeight(kg: kg, date: date)
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
        await metricsProvider?.writeWorkout(
            type: workout.type, minutes: workout.durationMinutes,
            calories: workout.caloriesBurned, date: workout.date
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

    // MARK: - Menstrual cycle

    /// Period tracking is shown only for users whose profile gender is female;
    /// the store keeps the data regardless so a profile change never loses it.

    public var sortedCycleEntries: [CycleEntry] {
        cycleEntries.sorted { $0.startDate > $1.startDate }
    }

    /// Cycle-day, phase, next-period and fertile-window projection, or nil
    /// until at least one period is logged.
    public func cyclePrediction(asOf now: Date = Date()) -> CyclePrediction? {
        CyclePredictor.predict(cycleEntries, asOf: now)
    }

    /// Logs a new period start (or updates the same-day entry). Keeps the list
    /// newest-first in memory.
    public func logPeriod(
        start: Date = Date(),
        end: Date? = nil,
        flow: FlowLevel = .medium,
        symptoms: [String] = [],
        note: String = ""
    ) async throws {
        let key = DayKey.make(start)
        let existingID = cycleEntries.first { $0.startKey == key }?.id
        let entry = CycleEntry(
            id: existingID ?? CycleEntry.newID(),
            startDate: start, endDate: end, flow: flow, symptoms: symptoms, note: note
        )
        try await database.writer.write { db in try entry.save(db) }
        cycleEntries.removeAll { $0.startKey == key }
        cycleEntries.append(entry)
        cycleEntries.sort { $0.startDate > $1.startDate }
        engram?.note(
            agentId: SphereType.health.rawValue,
            content: "Logged period start (\(flow.label.lowercased()) flow)",
            tags: ["log", "health", "cycle"]
        )
    }

    /// Sets the end date of a logged period (marks it finished).
    public func endPeriod(id: String, end: Date = Date()) async throws {
        guard let existing = cycleEntries.first(where: { $0.id == id }) else { return }
        let updated = CycleEntry(
            id: existing.id, startDate: existing.startDate, endDate: end,
            flow: existing.flow, symptoms: existing.symptoms, note: existing.note
        )
        try await database.writer.write { db in try updated.save(db) }
        cycleEntries = cycleEntries.map { $0.id == id ? updated : $0 }
    }

    public func removeCycleEntry(id: String) async throws {
        _ = try await database.writer.write { db in try CycleEntry.deleteOne(db, key: id) }
        cycleEntries.removeAll { $0.id == id }
    }

    public var hasHealthProvider: Bool { metricsProvider != nil }

    /// Reads menstrual flow from HealthKit, groups it into periods, and logs any
    /// whose start day isn't already recorded (manual entries are untouched).
    /// Returns how many periods were imported.
    @discardableResult
    public func importCycleFromHealth(days: Int = 120) async -> Int {
        guard let metricsProvider else { return 0 }
        _ = await metricsProvider.requestAuthorization()
        let flowDays = await metricsProvider.recentCycleFlow(days: days)
        let periods = CycleImport.periods(from: flowDays)
        guard !periods.isEmpty else { return 0 }

        var imported = 0
        for period in periods {
            // Skip any period whose date range overlaps an already-logged one, so
            // a manual entry starting a day off from Health isn't duplicated.
            let overlaps = cycleEntries.contains { existing in
                let existingEnd = existing.endDate ?? existing.startDate
                return period.start <= existingEnd && period.end >= existing.startDate
            }
            guard !overlaps else { continue }
            try? await logPeriod(
                start: period.start,
                end: period.end == period.start ? nil : period.end,
                flow: period.flow, note: "From Apple Health"
            )
            imported += 1
        }
        return imported
    }

    // MARK: - Energy & meal (one-tap 1–5 logs)

    public func todayEnergy(asOf now: Date = Date()) -> Int? { energyLevels[DayKey.make(now)] }
    public func todayMeal(asOf now: Date = Date()) -> Int? { mealQuality[DayKey.make(now)] }

    public func logEnergy(_ level: Int, on date: Date = Date()) async throws {
        try await upsertDayValue(table: "energy_levels", column: "level", value: level, date: date)
        energyLevels[DayKey.make(date)] = level
    }

    public func logMeal(_ quality: Int, on date: Date = Date()) async throws {
        try await upsertDayValue(table: "meal_quality", column: "quality", value: quality, date: date)
        mealQuality[DayKey.make(date)] = quality
    }

    /// Trailing-7-day series (oldest first, nil = no entry) for the insight
    /// engine (Stage 6).
    public func last7Energy(asOf now: Date = Date()) -> [Int?] {
        (0..<7).reversed().map { energyLevels[DayKey.make(now.addingTimeInterval(Double(-$0) * 86_400))] }
    }

    private func upsertDayValue(table: String, column: String, value: Int, date: Date) async throws {
        let key = DayKey.make(date)
        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT INTO \(table) (dateKey, \(column)) VALUES (?, ?) "
                    + "ON CONFLICT(dateKey) DO UPDATE SET \(column) = excluded.\(column)",
                arguments: [key, value]
            )
        }
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
                    name: "log_period",
                    description: "Record the start of the user's menstrual period today. "
                        + "flow is light, medium, or heavy (default medium). Use when the "
                        + "user mentions their period started.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "flow": [
                                "type": "string",
                                "enum": ["light", "medium", "heavy"],
                                "description": "Flow intensity",
                            ],
                        ],
                        "required": [],
                    ]
                ),
                spheres: [.health],
                confirmation: { input in
                    let flow = input["flow"]?.stringValue ?? "medium"
                    return "Logged period start (\(flow) flow)"
                },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    let flow = FlowLevel(rawValue: input["flow"]?.stringValue ?? "medium") ?? .medium
                    try await self.logPeriod(flow: flow)
                    let prediction = await self.cyclePrediction()
                    var result: [String: JSONValue] = ["ok": true]
                    if let prediction {
                        result["cycleDay"] = .number(Double(prediction.currentCycleDay))
                        result["nextPeriodInDays"] = .number(Double(prediction.daysUntilNextPeriod))
                    }
                    return JSONValue.object(result).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "log_energy",
                    description: "Record the user's energy level today on a 1–5 scale "
                        + "(1 = drained, 5 = energized).",
                    inputSchema: [
                        "type": "object",
                        "properties": ["level": ["type": "integer", "minimum": 1, "maximum": 5]],
                        "required": ["level"],
                    ]
                ),
                spheres: [.health],
                confirmation: { input in "Logged energy \(input["level"]?.intValue ?? 0)/5" },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let level = input["level"]?.intValue, (1...5).contains(level) else {
                        throw AgentToolInputError("level is required (1–5)")
                    }
                    try await self.logEnergy(level)
                    return JSONValue.object(["ok": true, "level": .number(Double(level))]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "log_meal",
                    description: "Record how well the user ate today on a 1–5 quality scale "
                        + "(1 = poor, 5 = great). Not calorie counting.",
                    inputSchema: [
                        "type": "object",
                        "properties": ["quality": ["type": "integer", "minimum": 1, "maximum": 5]],
                        "required": ["quality"],
                    ]
                ),
                spheres: [.health],
                confirmation: { input in "Logged meal quality \(input["quality"]?.intValue ?? 0)/5" },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let quality = input["quality"]?.intValue, (1...5).contains(quality) else {
                        throw AgentToolInputError("quality is required (1–5)")
                    }
                    try await self.logMeal(quality)
                    return JSONValue.object(["ok": true, "quality": .number(Double(quality))]).encodedString()
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
        if let energy = todayEnergy() { snapshot["energyToday"] = .number(Double(energy)) }
        if let meal = todayMeal() { snapshot["mealQualityToday"] = .number(Double(meal)) }
        if let cycle = cyclePrediction() {
            snapshot["cycle"] = .object([
                "day": .number(Double(cycle.currentCycleDay)),
                "phase": .string(cycle.phase.label),
                "onPeriod": .bool(cycle.isOnPeriod),
                "nextPeriodInDays": .number(Double(cycle.daysUntilNextPeriod)),
                "averageCycleLength": .number(Double(cycle.averageCycleLength)),
            ])
        }
        return JSONValue.object(snapshot).encodedString()
    }
}

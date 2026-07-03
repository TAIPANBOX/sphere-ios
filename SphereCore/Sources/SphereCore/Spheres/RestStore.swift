import Foundation
import GRDB
import Observation

/// Rest sphere store: sleep log with recovery levels, sleep schedule,
/// digital-detox days, anti-burnout work hours, and weekend plans.
/// Follows the golden-template shape (docs/HANDOFF.md).
@MainActor
@Observable
public final class RestStore {
    /// Newest first.
    public private(set) var sleepEntries: [SleepEntry] = []
    public private(set) var schedule = SleepSchedule()
    public private(set) var detoxDays: Set<String> = []
    public private(set) var workHours: [String: Double] = [:]
    public private(set) var weekendPlans: [String: WeekendPlan] = [:]

    private let database: AppDatabase
    private let engram: EngramStore?

    public init(database: AppDatabase, engram: EngramStore? = nil) {
        self.database = database
        self.engram = engram
    }

    public func load() async throws {
        let (entries, schedule, detox, work, weekends) = try await database.writer.read { db in
            (
                try SleepEntry.fetchAll(db, sql: "SELECT * FROM sleep_entries ORDER BY date DESC, rowid DESC"),
                try SleepSchedule.fetchOne(db, key: "main"),
                try String.fetchAll(db, sql: "SELECT dateKey FROM detox_days"),
                // Row is not Sendable; map to pairs inside the closure so the
                // async read overload applies.
                try Row.fetchAll(db, sql: "SELECT dateKey, hours FROM work_hours")
                    .map { ($0["dateKey"] as String, $0["hours"] as Double) },
                try WeekendPlan.fetchAll(db)
            )
        }
        sleepEntries = entries
        if let schedule { self.schedule = schedule }
        detoxDays = Set(detox)
        workHours = Dictionary(uniqueKeysWithValues: work)
        weekendPlans = Dictionary(uniqueKeysWithValues: weekends.map { ($0.weekKey, $0) })
    }

    // MARK: - Sleep log

    public func add(_ entry: SleepEntry) async throws {
        try await database.writer.write { db in try entry.insert(db) }
        sleepEntries.insert(entry, at: 0)
        engram?.note(
            agentId: SphereType.rest.rawValue,
            content: "Slept \(String(format: "%.1f", entry.hoursSlept))h, felt \(entry.recovery.rawValue)",
            tags: ["log", "rest", "sleep"]
        )
    }

    public func remove(id: String) async throws {
        _ = try await database.writer.write { db in try SleepEntry.deleteOne(db, key: id) }
        sleepEntries.removeAll { $0.id == id }
    }

    public func last7(asOf now: Date = Date()) -> [SleepEntry] {
        let cutoff = now.addingTimeInterval(-7 * 86_400)
        return sleepEntries.filter { $0.date > cutoff }
    }

    public func avgHoursLast7(asOf now: Date = Date()) -> Double {
        let entries = last7(asOf: now)
        guard !entries.isEmpty else { return 0 }
        return entries.reduce(0) { $0 + $1.hoursSlept } / Double(entries.count)
    }

    public func avgRecoveryLast7(asOf now: Date = Date()) -> RecoveryLevel {
        let entries = last7(asOf: now)
        guard !entries.isEmpty else { return .good }
        let average = Double(entries.reduce(0) { $0 + $1.recovery.score }) / Double(entries.count)
        if average >= 3.5 { return .excellent }
        if average >= 2.5 { return .good }
        if average >= 1.5 { return .fair }
        return .poor
    }

    /// Recovery Score 0–100 (formula from the Flutter rest screen):
    /// sleep vs 8 h goal is worth 60 points, low stress (0–10 scale, from
    /// the mindfulness sphere when ported) is worth 40; unknown stress
    /// contributes the neutral 20.
    public func recoveryScore(stressLevel: Int? = nil, asOf now: Date = Date()) -> Int {
        let sleepPoints = Int((min(max(avgHoursLast7(asOf: now) / 8, 0), 1) * 60).rounded())
        let stressPoints = stressLevel.map { Int((Double(10 - $0) / 10 * 40).rounded()) } ?? 20
        return min(max(sleepPoints + stressPoints, 0), 100)
    }

    // MARK: - Schedule

    public func setBedtime(hour: Int, minute: Int) async throws {
        schedule.bedtimeHour = hour
        schedule.bedtimeMinute = minute
        try await saveSchedule()
    }

    public func setWakeTime(hour: Int, minute: Int) async throws {
        schedule.wakeHour = hour
        schedule.wakeMinute = minute
        try await saveSchedule()
    }

    public func setGoal(hours: Double) async throws {
        schedule.goalHours = hours
        try await saveSchedule()
    }

    public func toggleReminders() async throws {
        schedule.remindersEnabled.toggle()
        try await saveSchedule()
    }

    private func saveSchedule() async throws {
        try await database.writer.write { [schedule] db in try schedule.save(db) }
    }

    // MARK: - Digital detox

    public func isDetoxDay(_ date: Date = Date()) -> Bool {
        detoxDays.contains(DayKey.make(date))
    }

    public func toggleDetox(on date: Date = Date()) async throws {
        let key = DayKey.make(date)
        if detoxDays.contains(key) {
            try await database.writer.write { db in
                try db.execute(sql: "DELETE FROM detox_days WHERE dateKey = ?", arguments: [key])
            }
            detoxDays.remove(key)
        } else {
            try await database.writer.write { db in
                try db.execute(sql: "INSERT INTO detox_days (dateKey) VALUES (?)", arguments: [key])
            }
            detoxDays.insert(key)
        }
    }

    /// Consecutive detox days ending today.
    public func detoxStreak(asOf now: Date = Date()) -> Int {
        var streak = 0
        var day = now
        while detoxDays.contains(DayKey.make(day)) {
            streak += 1
            day = day.addingTimeInterval(-86_400)
        }
        return streak
    }

    // MARK: - Anti-burnout work hours

    public func logWorkHours(_ hours: Double, on date: Date = Date()) async throws {
        let key = DayKey.make(date)
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO work_hours (dateKey, hours) VALUES (?, ?)
                    ON CONFLICT(dateKey) DO UPDATE SET hours = excluded.hours
                    """,
                arguments: [key, hours]
            )
        }
        workHours[key] = hours
    }

    public func weeklyWorkHours(asOf now: Date = Date()) -> Double {
        (0..<7).reduce(0) { total, daysAgo in
            total + (workHours[DayKey.make(now.addingTimeInterval(Double(-daysAgo) * 86_400))] ?? 0)
        }
    }

    // MARK: - Weekend plans

    /// Monday-anchored week key, e.g. "2026-W07-06".
    public nonisolated func currentWeekKey(asOf now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let parts = calendar.dateComponents([.year, .month, .day], from: monday)
        return String(format: "%04d-W%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public func currentWeekendPlan(asOf now: Date = Date()) -> WeekendPlan? {
        weekendPlans[currentWeekKey(asOf: now)]
    }

    public func saveWeekendPlan(_ plan: WeekendPlan) async throws {
        try await database.writer.write { db in try plan.save(db) }
        weekendPlans[plan.weekKey] = plan
    }

    public func addWeekendActivity(_ activity: String, asOf now: Date = Date()) async throws {
        let key = currentWeekKey(asOf: now)
        var plan = weekendPlans[key] ?? WeekendPlan(weekKey: key)
        plan.activities.append(activity)
        try await saveWeekendPlan(plan)
    }

    public func removeWeekendActivity(at index: Int, asOf now: Date = Date()) async throws {
        let key = currentWeekKey(asOf: now)
        guard var plan = weekendPlans[key], plan.activities.indices.contains(index) else { return }
        plan.activities.remove(at: index)
        try await saveWeekendPlan(plan)
    }

    // MARK: - Agent tools

    public nonisolated var tools: [SphereTool] {
        [
            SphereTool(
                definition: LLMTool(
                    name: "log_sleep",
                    description: "Record last night's sleep: hours slept and how rested the "
                        + "user feels (poor, fair, good, excellent). Use when the user "
                        + "mentions how they slept.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "hours": ["type": "number", "minimum": 0, "maximum": 24],
                            "recovery": [
                                "type": "string",
                                "enum": ["poor", "fair", "good", "excellent"],
                            ],
                            "note": ["type": "string"],
                        ],
                        "required": ["hours"],
                    ]
                ),
                spheres: [.rest],
                confirmation: { input in
                    "Logged \(input["hours"]?.doubleValue.map { String(format: "%g", $0) } ?? "?")h sleep"
                },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let hours = input["hours"]?.doubleValue, (0...24).contains(hours) else {
                        throw AgentToolInputError("hours is required (0–24)")
                    }
                    let entry = SleepEntry(
                        id: SleepEntry.newID(),
                        date: Date(),
                        hoursSlept: hours,
                        recovery: input["recovery"]?.stringValue
                            .flatMap(RecoveryLevel.init(rawValue:)) ?? .good,
                        note: input["note"]?.stringValue ?? ""
                    )
                    try await self.add(entry)
                    return JSONValue.object(["ok": true, "id": .string(entry.id)]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "get_rest_summary",
                    description: "Look up the user's rest state: 7-day average sleep, "
                        + "recovery level, sleep schedule, detox streak, and weekly work "
                        + "hours. Use before discussing sleep or recovery.",
                    inputSchema: ["type": "object", "properties": [:], "required": []]
                ),
                spheres: [.rest],
                silent: true,
                handler: { [weak self] _ in
                    guard let self else { throw CancellationError() }
                    return await self.restSummaryJSON()
                }
            ),
        ]
    }

    private func restSummaryJSON() -> String {
        JSONValue.object([
            "avgSleepHoursLast7": .number((avgHoursLast7() * 10).rounded() / 10),
            "recoveryLevel": .string(avgRecoveryLast7().rawValue),
            "recoveryScore": .number(Double(recoveryScore())),
            "schedule": .object([
                "bedtime": .string(schedule.bedtimeLabel),
                "wake": .string(schedule.wakeLabel),
                "goalHours": .number(schedule.goalHours),
            ]),
            "detoxStreakDays": .number(Double(detoxStreak())),
            "weeklyWorkHours": .number(weeklyWorkHours()),
            "recentSleep": .array(sleepEntries.prefix(7).map { entry in
                .object([
                    "date": .string(DayKey.make(entry.date)),
                    "hours": .number(entry.hoursSlept),
                    "recovery": .string(entry.recovery.rawValue),
                ])
            }),
        ]).encodedString()
    }
}

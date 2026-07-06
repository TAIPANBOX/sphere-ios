import Foundation
import Observation

/// Golden-template sphere store. Every sphere follows this shape:
/// `@MainActor @Observable` state + async mutations persisting to
/// ``AppDatabase`` + ``EngramStore/note(agentId:content:tags:salience:)`` on
/// significant mutations + a `tools` catalogue the agent can invoke.
@MainActor
@Observable
public final class GoalsStore {
    public private(set) var goals: [Goal] = []
    public private(set) var habits: [Habit] = []
    public private(set) var antiGoals: [AntiGoal] = []

    private let database: AppDatabase
    private let engram: EngramStore?

    public init(database: AppDatabase, engram: EngramStore? = nil) {
        self.database = database
        self.engram = engram
    }

    public func load() async throws {
        let (goals, habits, antiGoals) = try await database.writer.read { db in
            (try Goal.fetchAll(db), try Habit.fetchAll(db), try AntiGoal.fetchAll(db))
        }
        self.goals = goals
        self.habits = habits
        self.antiGoals = antiGoals
    }

    // MARK: - Anti-goals, why, stalled (gems)

    public func addAntiGoal(_ antiGoal: AntiGoal) async throws {
        try await database.writer.write { db in try antiGoal.insert(db) }
        antiGoals.append(antiGoal)
    }

    public func removeAntiGoal(id: String) async throws {
        _ = try await database.writer.write { db in try AntiGoal.deleteOne(db, key: id) }
        antiGoals.removeAll { $0.id == id }
    }

    /// Active goals stuck under `threshold`% — their `why` is worth resurfacing.
    public func stalledGoals(threshold: Int = 20) -> [Goal] {
        goals.filter { $0.status == .active && $0.progressPercent < threshold }
    }

    // MARK: - Goals

    public func add(_ goal: Goal) async throws {
        try await database.writer.write { db in try goal.insert(db) }
        goals.append(goal)
        engram?.note(
            agentId: SphereType.goals.rawValue,
            content: "New goal set: \(goal.title) (\(goal.horizon.rawValue))",
            tags: ["log", "goals", "goal"],
            salience: 0.75
        )
    }

    public func update(_ goal: Goal) async throws {
        try await database.writer.write { db in try goal.save(db) }
        goals = goals.map { $0.id == goal.id ? goal : $0 }
    }

    public func remove(id: String) async throws {
        _ = try await database.writer.write { db in try Goal.deleteOne(db, key: id) }
        goals.removeAll { $0.id == id }
    }

    public func setProgress(id: String, percent: Int) async throws {
        guard var goal = goals.first(where: { $0.id == id }) else { return }
        goal.progressPercent = min(max(percent, 0), 100)
        goal.status = goal.progressPercent >= 100 ? .completed : .active
        try await update(goal)
    }

    public func toggleStatus(id: String) async throws {
        guard var goal = goals.first(where: { $0.id == id }) else { return }
        goal.status = goal.status == .active ? .paused : .active
        try await update(goal)
    }

    /// Mean progress across non-paused goals (the Life Progress number).
    public var overallProgress: Int {
        let counted = goals.filter { $0.status != .paused }
        guard !counted.isEmpty else { return 0 }
        return counted.map(\.progressPercent).reduce(0, +) / counted.count
    }

    // MARK: - Habits

    public func addHabit(_ habit: Habit) async throws {
        try await database.writer.write { db in try habit.insert(db) }
        habits.append(habit)
    }

    public func removeHabit(id: String) async throws {
        _ = try await database.writer.write { db in try Habit.deleteOne(db, key: id) }
        habits.removeAll { $0.id == id }
    }

    public func toggleHabit(id: String, on date: Date = Date()) async throws {
        guard let habit = habits.first(where: { $0.id == id }) else { return }
        let toggled = habit.checkedIn(on: date)
            ? habit.uncheckingIn(on: date)
            : habit.checkingIn(on: date)
        try await database.writer.write { db in try toggled.save(db) }
        habits = habits.map { $0.id == id ? toggled : $0 }
    }

    /// Idempotently checks a habit in for `date`. Unlike `toggleHabit`, a
    /// second call is a no-op — used by the notification "Done" action, whose
    /// delivery is not guaranteed to happen exactly once.
    public func checkInHabit(id: String, on date: Date = Date()) async throws {
        guard let habit = habits.first(where: { $0.id == id }), !habit.checkedIn(on: date)
        else { return }
        let checked = habit.checkingIn(on: date)
        try await database.writer.write { db in try checked.save(db) }
        habits = habits.map { $0.id == id ? checked : $0 }
    }

    // MARK: - Agent tools

    /// Tools this sphere contributes to the agent's registry.
    public nonisolated var tools: [SphereTool] {
        [
            SphereTool(
                definition: LLMTool(
                    name: "add_goal",
                    description: "Create a new life goal. horizon is one of month, quarter, "
                        + "year, threeYears (default year).",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string", "minLength": 1],
                            "description": ["type": "string"],
                            "horizon": [
                                "type": "string",
                                "enum": ["month", "quarter", "year", "threeYears"],
                            ],
                            "emoji": ["type": "string", "description": "Optional emoji"],
                        ],
                        "required": ["title"],
                    ]
                ),
                spheres: [.goals],
                confirmation: { input in
                    "Added goal: \(input["title"]?.stringValue ?? "")"
                },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let title = input["title"]?.stringValue, !title.isEmpty else {
                        throw AgentToolInputError("title is required")
                    }
                    let goal = Goal(
                        id: Goal.newID(),
                        title: title,
                        description: input["description"]?.stringValue ?? "",
                        emoji: input["emoji"]?.stringValue ?? "🎯",
                        horizon: input["horizon"]?.stringValue.flatMap(GoalHorizon.init(rawValue:)) ?? .year
                    )
                    try await self.add(goal)
                    return JSONValue.object(["ok": true, "id": .string(goal.id)]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "list_goals",
                    description: "List the user's goals with their progress, horizon, and "
                        + "status. Use before discussing goals or progress.",
                    inputSchema: ["type": "object", "properties": [:], "required": []]
                ),
                spheres: [.goals],
                silent: true,
                handler: { [weak self] _ in
                    guard let self else { throw CancellationError() }
                    return await self.goalsSnapshotJSON()
                }
            ),
        ]
    }

    private func goalsSnapshotJSON() -> String {
        JSONValue.object([
            "count": .number(Double(goals.count)),
            "goals": .array(goals.map { goal in
                .object([
                    "title": .string(goal.title),
                    "progress": .number(Double(goal.progressPercent)),
                    "horizon": .string(goal.horizon.rawValue),
                    "status": .string(goal.status.rawValue),
                ])
            }),
        ]).encodedString()
    }
}

public struct AgentToolInputError: Error, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

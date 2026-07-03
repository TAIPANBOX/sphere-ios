import Foundation
import GRDB
import Observation

/// Career sphere store: task manager, projects with progress/deadlines, and
/// the interviews pipeline. Follows the golden-template shape
/// (docs/HANDOFF.md).
@MainActor
@Observable
public final class CareerStore {
    /// Newest first, matching the feed order.
    public private(set) var tasks: [CareerTask] = []
    public private(set) var projects: [CareerProject] = []
    public private(set) var interviews: [Interview] = []

    private let database: AppDatabase
    private let engram: EngramStore?

    public init(database: AppDatabase, engram: EngramStore? = nil) {
        self.database = database
        self.engram = engram
    }

    public func load() async throws {
        let (tasks, projects, interviews) = try await database.writer.read { db in
            (
                try CareerTask.fetchAll(db, sql: "SELECT * FROM career_tasks ORDER BY createdAt DESC, rowid DESC"),
                try CareerProject.fetchAll(db),
                try Interview.fetchAll(db)
            )
        }
        self.tasks = tasks
        self.projects = projects
        self.interviews = interviews
    }

    // MARK: - Tasks

    public func add(_ task: CareerTask) async throws {
        try await database.writer.write { db in try task.insert(db) }
        tasks.insert(task, at: 0)
        engram?.note(
            agentId: SphereType.career.rawValue,
            content: "New career task: \(task.title)"
                + (task.project.isEmpty ? "" : " (\(task.project))"),
            tags: ["log", "career", "task"]
        )
    }

    public func update(_ task: CareerTask) async throws {
        try await database.writer.write { db in try task.save(db) }
        tasks = tasks.map { $0.id == task.id ? task : $0 }
    }

    public func remove(id: String) async throws {
        _ = try await database.writer.write { db in try CareerTask.deleteOne(db, key: id) }
        tasks.removeAll { $0.id == id }
    }

    public func toggleStatus(id: String) async throws {
        guard var task = tasks.first(where: { $0.id == id }) else { return }
        task.status = task.status == .done ? .todo : .done
        try await update(task)
    }

    public var openTasks: [CareerTask] {
        tasks.filter { $0.status != .done }
    }

    public var doneCount: Int {
        tasks.count { $0.status == .done }
    }

    public func overdueCount(asOf now: Date = Date()) -> Int {
        tasks.count { $0.isOverdue(asOf: now) }
    }

    /// Open tasks that are unscheduled or due today (feeds Today's Focus).
    public func todayTasks(asOf now: Date = Date()) -> [CareerTask] {
        tasks.filter { task in
            guard task.status != .done else { return false }
            guard let dueDate = task.dueDate else { return true }
            return Calendar.current.isDate(dueDate, inSameDayAs: now)
        }
    }

    // MARK: - Projects

    public func addProject(_ project: CareerProject) async throws {
        try await database.writer.write { db in try project.insert(db) }
        projects.append(project)
    }

    public func updateProject(_ project: CareerProject) async throws {
        try await database.writer.write { db in try project.save(db) }
        projects = projects.map { $0.id == project.id ? project : $0 }
    }

    public func removeProject(id: String) async throws {
        _ = try await database.writer.write { db in try CareerProject.deleteOne(db, key: id) }
        projects.removeAll { $0.id == id }
    }

    public var activeProjects: [CareerProject] {
        projects.filter { $0.status == .active }
    }

    // MARK: - Interviews

    public func addInterview(_ interview: Interview) async throws {
        try await database.writer.write { db in try interview.insert(db) }
        interviews.append(interview)
    }

    public func setInterviewStatus(id: String, status: InterviewStatus) async throws {
        guard var interview = interviews.first(where: { $0.id == id }) else { return }
        interview.status = status
        try await database.writer.write { [interview] db in try interview.save(db) }
        interviews = interviews.map { $0.id == id ? interview : $0 }
    }

    public func removeInterview(id: String) async throws {
        _ = try await database.writer.write { db in try Interview.deleteOne(db, key: id) }
        interviews.removeAll { $0.id == id }
    }

    // MARK: - Agent tools

    public nonisolated var tools: [SphereTool] {
        [
            SphereTool(
                definition: LLMTool(
                    name: "add_career_task",
                    description: "Create a new career task. priority is one of low, medium, "
                        + "high, urgent (default medium).",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string", "minLength": 1],
                            "project": ["type": "string"],
                            "priority": [
                                "type": "string",
                                "enum": ["low", "medium", "high", "urgent"],
                            ],
                            "dueDate": [
                                "type": "string",
                                "description": "Optional ISO-8601 date (YYYY-MM-DD)",
                            ],
                        ],
                        "required": ["title"],
                    ]
                ),
                spheres: [.career],
                confirmation: { input in
                    "Added career task: \(input["title"]?.stringValue ?? "")"
                },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let title = input["title"]?.stringValue, !title.isEmpty else {
                        throw AgentToolInputError("title is required")
                    }
                    let task = CareerTask(
                        id: CareerTask.newID(),
                        title: title,
                        project: input["project"]?.stringValue ?? "",
                        priority: input["priority"]?.stringValue
                            .flatMap(TaskPriority.init(rawValue:)) ?? .medium,
                        dueDate: input["dueDate"]?.stringValue.flatMap(Self.parseDueDate),
                        createdAt: Date()
                    )
                    try await self.add(task)
                    return JSONValue.object(["ok": true, "id": .string(task.id)]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "list_career_tasks",
                    description: "List the user's open career tasks with priority, project, "
                        + "due date, and whether they are overdue.",
                    inputSchema: ["type": "object", "properties": [:], "required": []]
                ),
                spheres: [.career],
                silent: true,
                handler: { [weak self] _ in
                    guard let self else { throw CancellationError() }
                    return await self.tasksSnapshotJSON()
                }
            ),
        ]
    }

    /// Accepts the "YYYY-MM-DD" the schema asks for; anything unparseable is
    /// dropped (the task is still created), matching the Dart tryParse.
    nonisolated static func parseDueDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }

    private func tasksSnapshotJSON() -> String {
        let open = openTasks
        return JSONValue.object([
            "open": .number(Double(open.count)),
            "tasks": .array(open.map { task in
                var fields: [String: JSONValue] = [
                    "title": .string(task.title),
                    "project": .string(task.project),
                    "priority": .string(task.priority.rawValue),
                    "status": .string(task.status.rawValue),
                    "overdue": .bool(task.isOverdue()),
                ]
                if let dueDate = task.dueDate {
                    fields["due"] = .string(DayKey.make(dueDate))
                }
                return .object(fields)
            }),
        ]).encodedString()
    }
}

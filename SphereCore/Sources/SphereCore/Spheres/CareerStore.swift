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
    /// Newest first.
    public private(set) var achievements: [Achievement] = []
    public private(set) var network: [NetworkContact] = []
    public private(set) var careerSkills: [CareerSkill] = []
    public private(set) var salaryHistory: [SalaryEntry] = []
    public private(set) var careerGoals: [CareerGoal] = []
    public private(set) var oneOnOnes: [OneOnOne] = []

    private let database: AppDatabase
    private let engram: EngramStore?
    private let remindersProvider: (any RemindersProviding)?

    public init(
        database: AppDatabase, engram: EngramStore? = nil,
        remindersProvider: (any RemindersProviding)? = nil
    ) {
        self.database = database
        self.engram = engram
        self.remindersProvider = remindersProvider
    }

    public func load() async throws {
        let (tasks, projects, interviews, achievements, network, skills, salary, goals, oneOnOnes) =
            try await database.writer.read { db in
                (
                    try CareerTask.fetchAll(db, sql: "SELECT * FROM career_tasks ORDER BY createdAt DESC, rowid DESC"),
                    try CareerProject.fetchAll(db),
                    try Interview.fetchAll(db),
                    try Achievement.fetchAll(db, sql: "SELECT * FROM achievements ORDER BY date DESC"),
                    try NetworkContact.fetchAll(db),
                    try CareerSkill.fetchAll(db),
                    try SalaryEntry.fetchAll(db, sql: "SELECT * FROM salary_entries ORDER BY date DESC"),
                    try CareerGoal.fetchAll(db),
                    try OneOnOne.fetchAll(db, sql: "SELECT * FROM one_on_ones ORDER BY date DESC")
                )
            }
        self.tasks = tasks
        self.projects = projects
        self.interviews = interviews
        self.achievements = achievements
        self.network = network
        self.careerSkills = skills
        self.salaryHistory = salary
        self.careerGoals = goals
        self.oneOnOnes = oneOnOnes
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

    // MARK: - Reminders import

    public var hasRemindersProvider: Bool { remindersProvider != nil }

    /// Requests Reminders access, pulls incomplete reminders, and adds any
    /// whose title doesn't already match an open task as a new Career task.
    /// Returns how many were imported.
    @discardableResult
    public func importRemindersFromDevice(now: Date = Date()) async -> Int {
        guard let remindersProvider else { return 0 }
        guard await remindersProvider.requestRemindersAccess() else { return 0 }
        let reminders = await remindersProvider.fetchIncompleteReminders()
        guard !reminders.isEmpty else { return 0 }

        let openTitles = openTasks.map(\.title)
        let fresh = ReminderImport.newTasks(from: reminders, existingTitles: openTitles)
        var imported = 0
        for reminder in fresh {
            let task = ReminderImport.makeTask(from: reminder, now: now)
            try? await add(task)
            imported += 1
        }
        return imported
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

    // MARK: - Achievements

    public func addAchievement(_ achievement: Achievement) async throws {
        try await database.writer.write { db in try achievement.insert(db) }
        achievements.insert(achievement, at: 0)
        achievements.sort { $0.date > $1.date }
        engram?.note(
            agentId: SphereType.career.rawValue,
            content: "Logged achievement: \(achievement.title)"
                + (achievement.impact.isEmpty ? "" : " — \(achievement.impact)"),
            tags: ["log", "career", "achievement"],
            salience: 0.75
        )
    }

    public func removeAchievement(id: String) async throws {
        _ = try await database.writer.write { db in try Achievement.deleteOne(db, key: id) }
        achievements.removeAll { $0.id == id }
    }

    // MARK: - Network

    public func addNetworkContact(_ contact: NetworkContact) async throws {
        try await database.writer.write { db in try contact.insert(db) }
        network.append(contact)
    }

    public func removeNetworkContact(id: String) async throws {
        _ = try await database.writer.write { db in try NetworkContact.deleteOne(db, key: id) }
        network.removeAll { $0.id == id }
    }

    public func markNetworkContacted(id: String, on date: Date = Date()) async throws {
        guard var contact = network.first(where: { $0.id == id }) else { return }
        contact.lastContact = date
        try await database.writer.write { [contact] db in try contact.save(db) }
        network = network.map { $0.id == id ? contact : $0 }
    }

    /// Network contacts not touched in 60+ days, most overdue first.
    public func staleContacts(asOf now: Date = Date()) -> [NetworkContact] {
        network
            .filter { $0.daysSinceContact(asOf: now) >= 60 }
            .sorted { $0.daysSinceContact(asOf: now) > $1.daysSinceContact(asOf: now) }
    }

    // MARK: - Skills

    public func addSkill(_ skill: CareerSkill) async throws {
        try await database.writer.write { db in try skill.insert(db) }
        careerSkills.append(skill)
    }

    public func removeSkill(id: String) async throws {
        _ = try await database.writer.write { db in try CareerSkill.deleteOne(db, key: id) }
        careerSkills.removeAll { $0.id == id }
    }

    // MARK: - Salary history

    public func addSalary(_ entry: SalaryEntry) async throws {
        try await database.writer.write { db in try entry.insert(db) }
        salaryHistory.insert(entry, at: 0)
        salaryHistory.sort { $0.date > $1.date }
    }

    public func removeSalary(id: String) async throws {
        _ = try await database.writer.write { db in try SalaryEntry.deleteOne(db, key: id) }
        salaryHistory.removeAll { $0.id == id }
    }

    public var latestSalary: SalaryEntry? { salaryHistory.first }

    // MARK: - Career goals

    public func addCareerGoal(_ goal: CareerGoal) async throws {
        try await database.writer.write { db in try goal.insert(db) }
        careerGoals.append(goal)
    }

    public func removeCareerGoal(id: String) async throws {
        _ = try await database.writer.write { db in try CareerGoal.deleteOne(db, key: id) }
        careerGoals.removeAll { $0.id == id }
    }

    // MARK: - 1:1 notes

    public func addOneOnOne(_ note: OneOnOne) async throws {
        try await database.writer.write { db in try note.insert(db) }
        oneOnOnes.insert(note, at: 0)
        oneOnOnes.sort { $0.date > $1.date }
    }

    public func removeOneOnOne(id: String) async throws {
        _ = try await database.writer.write { db in try OneOnOne.deleteOne(db, key: id) }
        oneOnOnes.removeAll { $0.id == id }
    }

    // MARK: - Brag document (gem)

    /// Review-ready markdown of achievements + completed work.
    public func bragDocument(asOf now: Date = Date()) -> String {
        BragDocument.build(
            achievements: achievements,
            doneTasks: tasks.filter { $0.status == .done },
            now: now
        )
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
    /// Pinned to POSIX/Gregorian: the model sends ISO dates, and a device
    /// set to a Buddhist/Japanese calendar must not reinterpret the year.
    nonisolated static func parseDueDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
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

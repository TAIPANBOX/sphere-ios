import Foundation
import GRDB
import Observation

/// Creativity sphere store: creative projects with progress and
/// collaborators, plus quick idea capture. Follows the golden-template
/// shape (docs/HANDOFF.md).
@MainActor
@Observable
public final class CreativityStore {
    public private(set) var projects: [CreativeProject] = []
    public private(set) var ideas: [InspirationItem] = []
    public private(set) var portfolio: [PortfolioItem] = []
    public private(set) var sessions: [ProjectSession] = []

    private let database: AppDatabase
    private let engram: EngramStore?

    public init(database: AppDatabase, engram: EngramStore? = nil) {
        self.database = database
        self.engram = engram
    }

    public func load() async throws {
        let (projects, ideas, portfolio, sessions) = try await database.writer.read { db in
            (
                try CreativeProject.fetchAll(db),
                try InspirationItem.fetchAll(db),
                try PortfolioItem.fetchAll(db, sql: "SELECT * FROM portfolio_items ORDER BY date DESC"),
                try ProjectSession.fetchAll(db, sql: "SELECT * FROM project_sessions ORDER BY date DESC")
            )
        }
        self.projects = projects
        self.ideas = ideas
        self.portfolio = portfolio
        self.sessions = sessions
    }

    // MARK: - Portfolio

    public func addPortfolioItem(_ item: PortfolioItem) async throws {
        try await database.writer.write { db in try item.insert(db) }
        portfolio.insert(item, at: 0)
    }

    public func removePortfolioItem(id: String) async throws {
        _ = try await database.writer.write { db in try PortfolioItem.deleteOne(db, key: id) }
        portfolio.removeAll { $0.id == id }
    }

    // MARK: - Work sessions

    public func sessions(for projectId: String) -> [ProjectSession] {
        sessions.filter { $0.projectId == projectId }
    }

    /// Logs a work session and stamps the project's `lastWorkedOn`.
    public func logSession(projectId: String, minutes: Int, on date: Date = Date()) async throws {
        let session = ProjectSession(
            id: ProjectSession.newID(), projectId: projectId, date: date, minutes: max(minutes, 1)
        )
        try await database.writer.write { db in try session.insert(db) }
        sessions.insert(session, at: 0)
        if var project = projects.first(where: { $0.id == projectId }) {
            project.lastWorkedOn = date
            try? await update(project)
        }
    }

    public func removeSession(id: String) async throws {
        _ = try await database.writer.write { db in try ProjectSession.deleteOne(db, key: id) }
        sessions.removeAll { $0.id == id }
    }

    public func totalMinutes(for projectId: String) -> Int {
        sessions(for: projectId).reduce(0) { $0 + $1.minutes }
    }

    /// Total creative minutes logged this ISO week.
    public func minutesThisWeek(asOf now: Date = Date()) -> Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return sessions
            .filter { $0.date >= week.start && $0.date < week.end }
            .reduce(0) { $0 + $1.minutes }
    }

    /// Minutes logged per day for the trailing 7 days (oldest first).
    public func weeklyMinutes(asOf now: Date = Date()) -> [Int] {
        (0..<7).reversed().map { daysAgo in
            let key = DayKey.make(now.addingTimeInterval(Double(-daysAgo) * 86_400))
            return sessions.filter { DayKey.make($0.date) == key }.reduce(0) { $0 + $1.minutes }
        }
    }

    // MARK: - Projects

    public func add(_ project: CreativeProject) async throws {
        try await database.writer.write { db in try project.insert(db) }
        projects.append(project)
        engram?.note(
            agentId: SphereType.creativity.rawValue,
            content: "Started creative project: \(project.title) (\(project.type.rawValue))",
            tags: ["log", "creativity", "project"]
        )
    }

    public func update(_ project: CreativeProject) async throws {
        try await database.writer.write { db in try project.save(db) }
        projects = projects.map { $0.id == project.id ? project : $0 }
    }

    public func remove(id: String) async throws {
        _ = try await database.writer.write { db in try CreativeProject.deleteOne(db, key: id) }
        projects.removeAll { $0.id == id }
    }

    /// Clamps progress, completes at 100%, and stamps `lastWorkedOn`.
    public func setProgress(id: String, percent: Int, on date: Date = Date()) async throws {
        guard var project = projects.first(where: { $0.id == id }) else { return }
        project.progressPercent = min(max(percent, 0), 100)
        project.status = project.progressPercent >= 100 ? .completed : .inProgress
        project.lastWorkedOn = date
        try await update(project)
    }

    public func addCollaborator(id: String, name: String) async throws {
        guard var project = projects.first(where: { $0.id == id }) else { return }
        project.collaborators.append(name)
        try await update(project)
    }

    public func removeCollaborator(id: String, at index: Int) async throws {
        guard var project = projects.first(where: { $0.id == id }),
              project.collaborators.indices.contains(index)
        else { return }
        project.collaborators.remove(at: index)
        try await update(project)
    }

    public var inProgress: [CreativeProject] {
        projects.filter { $0.status == .inProgress }
    }

    public var ideaBacklog: [CreativeProject] {
        projects.filter { $0.status == .idea }
    }

    public var completed: [CreativeProject] {
        projects.filter { $0.status == .completed }
    }

    // MARK: - Ideas

    @discardableResult
    public func addIdea(_ content: String, tag: String = "Idea", on date: Date = Date()) async throws -> InspirationItem {
        let item = InspirationItem(id: InspirationItem.newID(), content: content, tag: tag, date: date)
        try await database.writer.write { db in try item.insert(db) }
        ideas.append(item)
        let preview = content.count > 120 ? String(content.prefix(120)) + "…" : content
        engram?.note(
            agentId: SphereType.creativity.rawValue,
            content: "Captured idea: \(preview)",
            tags: ["log", "creativity", "idea"]
        )
        return item
    }

    public func removeIdea(id: String) async throws {
        _ = try await database.writer.write { db in try InspirationItem.deleteOne(db, key: id) }
        ideas.removeAll { $0.id == id }
    }

    public var recentIdeas: [InspirationItem] {
        ideas.sorted { $0.date > $1.date }
    }

    // MARK: - Agent tools

    /// NEW relative to the Dart version (which had no creativity tools),
    /// following the wave-2 write + silent-lookup convention.
    public nonisolated var tools: [SphereTool] {
        [
            SphereTool(
                definition: LLMTool(
                    name: "capture_idea",
                    description: "Save a creative idea or inspiration for the user. Use when "
                        + "they share an idea worth keeping — a story concept, melody, "
                        + "photo subject, project thought.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "content": ["type": "string", "minLength": 1],
                            "tag": ["type": "string", "description": "e.g. Idea, Melody, Story"],
                        ],
                        "required": ["content"],
                    ]
                ),
                spheres: [.creativity],
                confirmation: { _ in "Captured the idea 💡" },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let content = input["content"]?.stringValue, !content.isEmpty else {
                        throw AgentToolInputError("content is required")
                    }
                    let item = try await self.addIdea(
                        content, tag: input["tag"]?.stringValue ?? "Idea"
                    )
                    return JSONValue.object(["ok": true, "id": .string(item.id)]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "get_creativity_summary",
                    description: "Look up the user's creative projects (with progress and "
                        + "status) and recently captured ideas. Use before discussing "
                        + "creative work.",
                    inputSchema: ["type": "object", "properties": [:], "required": []]
                ),
                spheres: [.creativity],
                silent: true,
                handler: { [weak self] _ in
                    guard let self else { throw CancellationError() }
                    return await self.creativitySummaryJSON()
                }
            ),
        ]
    }

    private func creativitySummaryJSON() -> String {
        JSONValue.object([
            "projects": .array(projects.map { project in
                .object([
                    "title": .string(project.title),
                    "type": .string(project.type.rawValue),
                    "status": .string(project.status.rawValue),
                    "progress": .number(Double(project.progressPercent)),
                ])
            }),
            "recentIdeas": .array(recentIdeas.prefix(5).map { idea in
                .object([
                    "content": .string(
                        idea.content.count > 120
                            ? String(idea.content.prefix(120)) + "…" : idea.content
                    ),
                    "tag": .string(idea.tag),
                ])
            }),
        ]).encodedString()
    }
}

import Foundation
import GRDB
import Observation

/// Hobbies sphere store: hobby list with weekly time targets and a session
/// log. Follows the golden-template shape (docs/HANDOFF.md).
@MainActor
@Observable
public final class HobbiesStore {
    public private(set) var hobbies: [Hobby] = []
    /// Newest first.
    public private(set) var sessions: [HobbySession] = []

    private let database: AppDatabase
    private let engram: EngramStore?

    public init(database: AppDatabase, engram: EngramStore? = nil) {
        self.database = database
        self.engram = engram
    }

    public func load() async throws {
        let (hobbies, sessions) = try await database.writer.read { db in
            (
                try Hobby.fetchAll(db),
                try HobbySession.fetchAll(db, sql: "SELECT * FROM hobby_sessions ORDER BY date DESC, rowid DESC")
            )
        }
        self.hobbies = hobbies
        self.sessions = sessions
    }

    // MARK: - Hobbies

    public func addHobby(_ hobby: Hobby) async throws {
        try await database.writer.write { db in try hobby.insert(db) }
        hobbies.append(hobby)
        engram?.note(
            agentId: SphereType.hobbies.rawValue,
            content: "Picked up a new hobby: \(hobby.name)",
            tags: ["log", "hobbies", "hobby"]
        )
    }

    public func updateHobby(_ hobby: Hobby) async throws {
        try await database.writer.write { db in try hobby.save(db) }
        hobbies = hobbies.map { $0.id == hobby.id ? hobby : $0 }
    }

    /// Removing a hobby cascades its sessions (Dart behavior).
    public func removeHobby(id: String) async throws {
        try await database.writer.write { db in
            _ = try Hobby.deleteOne(db, key: id)
            try db.execute(sql: "DELETE FROM hobby_sessions WHERE hobbyId = ?", arguments: [id])
        }
        hobbies.removeAll { $0.id == id }
        sessions.removeAll { $0.hobbyId == id }
    }

    public func toggleActive(id: String) async throws {
        guard var hobby = hobbies.first(where: { $0.id == id }) else { return }
        hobby.isActive.toggle()
        try await updateHobby(hobby)
    }

    public func setGoal(id: String, goal: String) async throws {
        guard var hobby = hobbies.first(where: { $0.id == id }) else { return }
        hobby.goal = goal
        try await updateHobby(hobby)
    }

    public func addEquipment(id: String, item: String) async throws {
        guard var hobby = hobbies.first(where: { $0.id == id }) else { return }
        hobby.equipment.append(item)
        try await updateHobby(hobby)
    }

    public func removeEquipment(id: String, at index: Int) async throws {
        guard var hobby = hobbies.first(where: { $0.id == id }),
              hobby.equipment.indices.contains(index)
        else { return }
        hobby.equipment.remove(at: index)
        try await updateHobby(hobby)
    }

    public func addResource(id: String, resource: String) async throws {
        guard var hobby = hobbies.first(where: { $0.id == id }) else { return }
        hobby.resources.append(resource)
        try await updateHobby(hobby)
    }

    public func removeResource(id: String, at index: Int) async throws {
        guard var hobby = hobbies.first(where: { $0.id == id }),
              hobby.resources.indices.contains(index)
        else { return }
        hobby.resources.remove(at: index)
        try await updateHobby(hobby)
    }

    // MARK: - Sessions

    public func logSession(_ session: HobbySession) async throws {
        try await database.writer.write { db in try session.insert(db) }
        sessions.insert(session, at: 0)
        let name = hobbies.first { $0.id == session.hobbyId }?.name ?? "hobby"
        engram?.note(
            agentId: SphereType.hobbies.rawValue,
            content: "\(name) session, \(session.durationMinutes) min"
                + (session.note.isEmpty ? "" : " — \(session.note)"),
            tags: ["log", "hobbies", "session"]
        )
    }

    public func removeSession(id: String) async throws {
        _ = try await database.writer.write { db in try HobbySession.deleteOne(db, key: id) }
        sessions.removeAll { $0.id == id }
    }

    public func weeklyMinutes(for hobbyId: String, asOf now: Date = Date()) -> Int {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        return sessions
            .filter { $0.hobbyId == hobbyId && $0.date > weekAgo }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    public func totalMinutes(for hobbyId: String) -> Int {
        sessions.filter { $0.hobbyId == hobbyId }.reduce(0) { $0 + $1.durationMinutes }
    }

    /// All hobbies' minutes over the trailing week (feeds the Life Score).
    public func totalWeeklyMinutes(asOf now: Date = Date()) -> Int {
        hobbies.reduce(0) { $0 + weeklyMinutes(for: $1.id, asOf: now) }
    }

    // MARK: - Agent tools

    /// NEW relative to the Dart version (which had no hobbies tools),
    /// following the wave-2 write + silent-lookup convention.
    public nonisolated var tools: [SphereTool] {
        [
            SphereTool(
                definition: LLMTool(
                    name: "log_hobby_session",
                    description: "Record time spent on one of the user's hobbies. hobby is "
                        + "matched by name (case-insensitive). Use when they mention "
                        + "practicing, playing, cooking, shooting photos, etc.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "hobby": ["type": "string", "description": "Hobby name, e.g. Guitar"],
                            "minutes": ["type": "integer", "minimum": 1, "maximum": 720],
                            "note": ["type": "string"],
                        ],
                        "required": ["hobby", "minutes"],
                    ]
                ),
                spheres: [.hobbies],
                confirmation: { input in
                    "Logged \(input["minutes"]?.intValue ?? 0) min of \(input["hobby"]?.stringValue ?? "hobby")"
                },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let name = input["hobby"]?.stringValue, !name.isEmpty else {
                        throw AgentToolInputError("hobby is required")
                    }
                    guard let minutes = input["minutes"]?.intValue, (1...720).contains(minutes) else {
                        throw AgentToolInputError("minutes is required (1–720)")
                    }
                    guard let hobby = await self.hobby(named: name) else {
                        let known = await self.hobbies.map(\.name).joined(separator: ", ")
                        throw AgentToolInputError(
                            "Unknown hobby \"\(name)\". Known hobbies: \(known.isEmpty ? "none yet" : known)"
                        )
                    }
                    let session = HobbySession(
                        id: HobbySession.newID(),
                        hobbyId: hobby.id,
                        durationMinutes: minutes,
                        date: Date(),
                        note: input["note"]?.stringValue ?? ""
                    )
                    try await self.logSession(session)
                    return JSONValue.object(["ok": true, "id": .string(session.id)]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "get_hobbies_summary",
                    description: "Look up the user's hobbies with weekly minutes vs target "
                        + "and recent sessions. Use before discussing hobbies or free time.",
                    inputSchema: ["type": "object", "properties": [:], "required": []]
                ),
                spheres: [.hobbies],
                silent: true,
                handler: { [weak self] _ in
                    guard let self else { throw CancellationError() }
                    return await self.hobbiesSummaryJSON()
                }
            ),
        ]
    }

    private func hobby(named name: String) -> Hobby? {
        hobbies.first { $0.name.lowercased() == name.lowercased() }
    }

    private func hobbiesSummaryJSON() -> String {
        JSONValue.object([
            "hobbies": .array(hobbies.map { hobby in
                .object([
                    "name": .string(hobby.name),
                    "active": .bool(hobby.isActive),
                    "weeklyMinutes": .number(Double(weeklyMinutes(for: hobby.id))),
                    "targetMinutesPerWeek": .number(Double(hobby.targetMinutesPerWeek)),
                ])
            }),
            "recentSessions": .array(sessions.prefix(5).map { session in
                .object([
                    "hobby": .string(hobbies.first { $0.id == session.hobbyId }?.name ?? "?"),
                    "minutes": .number(Double(session.durationMinutes)),
                    "date": .string(DayKey.make(session.date)),
                    "note": .string(session.note),
                ])
            }),
        ]).encodedString()
    }
}

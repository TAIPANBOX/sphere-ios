import Foundation
import GRDB
import Observation

/// Mindfulness sphere store: meditation sessions with streak, daily mood
/// check-in, stress levels, and the journal. Follows the golden-template
/// shape (docs/HANDOFF.md).
@MainActor
@Observable
public final class MindfulnessStore {
    /// Newest first.
    public private(set) var sessions: [MeditationSession] = []
    public private(set) var journal: [JournalEntry] = []
    public private(set) var moods: [String: Int] = [:]
    public private(set) var stress: [String: Int] = [:]
    public private(set) var gratitude: [GratitudeEntry] = []
    public private(set) var customAffirmations: [Affirmation] = []

    private let database: AppDatabase
    private let engram: EngramStore?

    public init(database: AppDatabase, engram: EngramStore? = nil) {
        self.database = database
        self.engram = engram
    }

    public func load() async throws {
        let (sessions, journal, moods, stress, gratitude, affirmations) =
            try await database.writer.read { db in
                (
                    try MeditationSession.fetchAll(db, sql: "SELECT * FROM meditation_sessions ORDER BY date DESC, rowid DESC"),
                    try JournalEntry.fetchAll(db),
                    try Row.fetchAll(db, sql: "SELECT dateKey, score FROM moods")
                        .map { ($0["dateKey"] as String, $0["score"] as Int) },
                    try Row.fetchAll(db, sql: "SELECT dateKey, level FROM stress_levels")
                        .map { ($0["dateKey"] as String, $0["level"] as Int) },
                    try GratitudeEntry.fetchAll(db, sql: "SELECT * FROM gratitude_entries ORDER BY date DESC"),
                    try Affirmation.fetchAll(db, sql: "SELECT * FROM affirmations WHERE isCustom = 1")
                )
            }
        self.sessions = sessions
        self.journal = journal
        self.moods = Dictionary(uniqueKeysWithValues: moods)
        self.stress = Dictionary(uniqueKeysWithValues: stress)
        self.gratitude = gratitude
        self.customAffirmations = affirmations
    }

    // MARK: - Gratitude & affirmations

    public func hasGratitudeToday(asOf now: Date = Date()) -> Bool {
        gratitude.contains { DayKey.make($0.date) == DayKey.make(now) }
    }

    public func addGratitude(_ content: String, on date: Date = Date()) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entry = GratitudeEntry(id: GratitudeEntry.newID(), date: date, content: trimmed)
        try await database.writer.write { db in try entry.insert(db) }
        gratitude.insert(entry, at: 0)
        engram?.note(
            agentId: SphereType.mindfulness.rawValue,
            content: "Grateful for: \(trimmed)",
            tags: ["log", "mindfulness", "gratitude"]
        )
    }

    public func removeGratitude(id: String) async throws {
        _ = try await database.writer.write { db in try GratitudeEntry.deleteOne(db, key: id) }
        gratitude.removeAll { $0.id == id }
    }

    /// The affirmation to show today (a user's own if they added any, else a
    /// built-in seed), stable through the day.
    public func dailyAffirmation(for date: Date = Date()) -> String {
        Affirmation.daily(for: date, custom: customAffirmations)
    }

    public func addAffirmation(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let affirmation = Affirmation(id: Affirmation.newID(), text: trimmed, isCustom: true)
        try await database.writer.write { db in try affirmation.insert(db) }
        customAffirmations.append(affirmation)
    }

    public func removeAffirmation(id: String) async throws {
        _ = try await database.writer.write { db in try Affirmation.deleteOne(db, key: id) }
        customAffirmations.removeAll { $0.id == id }
    }

    // MARK: - Meditation

    public func add(_ session: MeditationSession) async throws {
        try await database.writer.write { db in try session.insert(db) }
        sessions.insert(session, at: 0)
        engram?.note(
            agentId: SphereType.mindfulness.rawValue,
            content: "Meditated \(session.durationMinutes) min (\(session.type.rawValue))",
            tags: ["log", "mindfulness", "meditation"]
        )
    }

    public func remove(id: String) async throws {
        _ = try await database.writer.write { db in try MeditationSession.deleteOne(db, key: id) }
        sessions.removeAll { $0.id == id }
    }

    public var totalMinutes: Int {
        sessions.reduce(0) { $0 + $1.durationMinutes }
    }

    public func hasMeditated(on date: Date = Date()) -> Bool {
        let key = DayKey.make(date)
        // Focus/deep-work sessions are tracked separately and don't count as
        // meditation.
        return sessions.contains { $0.type != .focus && DayKey.make($0.date) == key }
    }

    /// Day keys the user was in sick/vacation mode — set by the app so a
    /// missed session during recovery bridges the streak instead of resetting
    /// it (forgiveness, N4). Empty by default = plain streak semantics.
    public var excusedStreakDays: Set<String> = []

    /// Consecutive days with a session, ending today (0 when none today),
    /// bridging any days excused by sick/vacation mode.
    public func currentStreak(asOf now: Date = Date()) -> Int {
        StreakPolicy.streak(
            asOf: now,
            isActive: { hasMeditated(on: $0) },
            isExcused: { excusedStreakDays.contains(DayKey.make($0)) }
        )
    }

    // MARK: - Focus sessions & discipline (Tysh-inspired)

    /// Focus/deep-work sessions are logged as meditation sessions of type
    /// `.focus`, so they reuse the same storage and streak machinery.
    public var focusSessions: [MeditationSession] {
        sessions.filter { $0.type == .focus }
    }

    public func focusMinutesToday(asOf now: Date = Date()) -> Int {
        let key = DayKey.make(now)
        return focusSessions
            .filter { DayKey.make($0.date) == key }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    public func hasFocusedToday(asOf now: Date = Date()) -> Bool {
        let key = DayKey.make(now)
        return focusSessions.contains { DayKey.make($0.date) == key }
    }

    /// Consecutive days with a focus session, bridging sick/vacation days.
    public func focusStreak(asOf now: Date = Date()) -> Int {
        StreakPolicy.streak(
            asOf: now,
            isActive: { day in
                let key = DayKey.make(day)
                return focusSessions.contains { DayKey.make($0.date) == key }
            },
            isExcused: { excusedStreakDays.contains(DayKey.make($0)) }
        )
    }

    /// Today's 0–100 discipline score from focus time, meditation, and streak.
    public func disciplineScore(asOf now: Date = Date()) -> Int {
        DisciplineScore.compute(
            focusMinutesToday: focusMinutesToday(asOf: now),
            meditatedToday: hasMeditated(on: now),
            focusStreakDays: focusStreak(asOf: now)
        )
    }

    /// Logs a completed focus session of `minutes`.
    public func logFocusSession(minutes: Int, note: String = "", on date: Date = Date()) async throws {
        try await add(MeditationSession(
            id: MeditationSession.newID(now: date),
            type: .focus,
            durationMinutes: max(minutes, 1),
            date: date,
            note: note
        ))
    }

    // MARK: - Mood

    public func todaysMood(asOf now: Date = Date()) -> Int? {
        moods[DayKey.make(now)]
    }

    /// Records today's mood on the 1–5 scale, overwriting earlier check-ins.
    public func setMood(_ score: Int, on date: Date = Date()) async throws {
        let key = DayKey.make(date)
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO moods (dateKey, score) VALUES (?, ?)
                    ON CONFLICT(dateKey) DO UPDATE SET score = excluded.score
                    """,
                arguments: [key, score]
            )
        }
        moods[key] = score
        engram?.note(
            agentId: SphereType.mindfulness.rawValue,
            content: "Logged mood: \(score)/5",
            tags: ["log", "mindfulness", "mood"]
        )
    }

    /// Mood scores for the trailing 7 days, oldest first (nil = no check-in).
    public func last7Moods(asOf now: Date = Date()) -> [Int?] {
        (0..<7).reversed().map { daysAgo in
            moods[DayKey.make(now.addingTimeInterval(Double(-daysAgo) * 86_400))]
        }
    }

    // MARK: - Stress

    public func todayStress(asOf now: Date = Date()) -> Int? {
        stress[DayKey.make(now)]
    }

    /// Records today's stress on the 1–10 scale.
    public func setStress(_ level: Int, on date: Date = Date()) async throws {
        let key = DayKey.make(date)
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO stress_levels (dateKey, level) VALUES (?, ?)
                    ON CONFLICT(dateKey) DO UPDATE SET level = excluded.level
                    """,
                arguments: [key, level]
            )
        }
        stress[key] = level
        engram?.note(
            agentId: SphereType.mindfulness.rawValue,
            content: "Logged stress level: \(level)/10",
            tags: ["log", "mindfulness", "stress"]
        )
    }

    /// Stress levels for the trailing 7 days, oldest first (0 = no entry),
    /// matching the Dart last7Days shape.
    public func last7Stress(asOf now: Date = Date()) -> [Int] {
        (0..<7).reversed().map { daysAgo in
            stress[DayKey.make(now.addingTimeInterval(Double(-daysAgo) * 86_400))] ?? 0
        }
    }

    // MARK: - Journal

    @discardableResult
    public func addJournal(_ text: String, on date: Date = Date()) async throws -> JournalEntry {
        let entry = JournalEntry(id: JournalEntry.newID(), date: date, text: text)
        try await database.writer.write { db in try entry.insert(db) }
        journal.append(entry)
        let preview = text.count > 200 ? String(text.prefix(200)) + "…" : text
        engram?.note(
            agentId: SphereType.mindfulness.rawValue,
            content: "Journal entry: \(preview)",
            tags: ["log", "mindfulness", "journal"]
        )
        return entry
    }

    public func removeJournal(id: String) async throws {
        _ = try await database.writer.write { db in try JournalEntry.deleteOne(db, key: id) }
        journal.removeAll { $0.id == id }
    }

    public var recentJournal: [JournalEntry] {
        journal.sorted { $0.date > $1.date }.prefix(10).map { $0 }
    }

    // MARK: - Agent tools (ported verbatim from sphere_tools.dart)

    public nonisolated var tools: [SphereTool] {
        [
            SphereTool(
                definition: LLMTool(
                    name: "log_meditation",
                    description: "Record that the user finished a meditation session. Use "
                        + "when they mention meditating or finishing a breathing exercise.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "minutes": ["type": "integer", "minimum": 1, "maximum": 240],
                            "type": [
                                "type": "string",
                                "enum": [
                                    "breathing", "bodyScan", "visualization",
                                    "lovingKindness", "focus", "sleep", "custom",
                                ],
                                "description": "Optional meditation style",
                            ],
                            "note": ["type": "string"],
                        ],
                        "required": ["minutes"],
                    ]
                ),
                spheres: [.mindfulness],
                confirmation: { input in
                    "Logged \(input["minutes"]?.intValue ?? 0)-min meditation"
                },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let minutes = input["minutes"]?.intValue, (1...240).contains(minutes) else {
                        throw AgentToolInputError("minutes is required (1–240)")
                    }
                    let session = MeditationSession(
                        id: MeditationSession.newID(),
                        type: input["type"]?.stringValue
                            .flatMap(MeditationType.init(rawValue:)) ?? .breathing,
                        durationMinutes: minutes,
                        date: Date(),
                        note: input["note"]?.stringValue ?? ""
                    )
                    try await self.add(session)
                    return JSONValue.object(["ok": true, "id": .string(session.id)]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "log_mood",
                    description: "Record the user's mood for today on a 1–5 scale (1 = low, "
                        + "5 = great). Overwrites any earlier entry for the same day.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "score": ["type": "integer", "minimum": 1, "maximum": 5],
                        ],
                        "required": ["score"],
                    ]
                ),
                spheres: [.mindfulness],
                confirmation: { input in
                    "Logged today's mood: \(input["score"]?.intValue ?? 0)/5"
                },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let score = input["score"]?.intValue, (1...5).contains(score) else {
                        throw AgentToolInputError("score is required (1–5)")
                    }
                    try await self.setMood(score)
                    return JSONValue.object(["ok": true, "score": .number(Double(score))]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "add_journal_entry",
                    description: "Save a journal entry on behalf of the user. Use when they "
                        + "share reflections, gratitude, or anything worth keeping.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "text": ["type": "string", "minLength": 1],
                        ],
                        "required": ["text"],
                    ]
                ),
                spheres: [.mindfulness],
                confirmation: { _ in "Saved journal entry" },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let text = input["text"]?.stringValue, !text.isEmpty else {
                        throw AgentToolInputError("text is required")
                    }
                    try await self.addJournal(text)
                    return JSONValue.object(["ok": true]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "get_mindfulness_summary",
                    description: "Look up the user's mindfulness state: meditation streak and "
                        + "total minutes, today's mood and stress, and recent journal entries.",
                    inputSchema: ["type": "object", "properties": [:], "required": []]
                ),
                spheres: [.mindfulness],
                silent: true,
                handler: { [weak self] _ in
                    guard let self else { throw CancellationError() }
                    return await self.mindfulnessSummaryJSON()
                }
            ),
        ]
    }

    private func mindfulnessSummaryJSON() -> String {
        var summary: [String: JSONValue] = [
            "meditationStreakDays": .number(Double(currentStreak())),
            "totalMeditationMinutes": .number(Double(totalMinutes)),
            "recentJournal": .array(recentJournal.prefix(3).map { entry in
                .object([
                    "date": .string(DayKey.make(entry.date)),
                    "text": .string(
                        entry.text.count > 160 ? String(entry.text.prefix(160)) + "…" : entry.text
                    ),
                ])
            }),
        ]
        if let mood = todaysMood() {
            summary["todayMood"] = .number(Double(mood))
        }
        if let stress = todayStress() {
            summary["todayStress"] = .number(Double(stress))
        }
        return JSONValue.object(summary).encodedString()
    }
}

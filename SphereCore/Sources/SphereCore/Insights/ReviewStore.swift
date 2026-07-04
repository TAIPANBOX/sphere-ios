import Foundation
import GRDB
import Observation

/// Builds the weekly digest, computes the Life Wheel comparison, and persists
/// saved reviews.
@MainActor
@Observable
public final class ReviewStore {
    public private(set) var reviews: [Review] = []

    private let database: AppDatabase
    private let home: HomeStore
    private let mindfulness: MindfulnessStore
    private let health: HealthStore
    private let rest: RestStore
    private let finance: FinanceStore
    private let insights: InsightsStore
    private let agent: AgentService?

    public init(
        database: AppDatabase, home: HomeStore, mindfulness: MindfulnessStore,
        health: HealthStore, rest: RestStore, finance: FinanceStore,
        insights: InsightsStore, agent: AgentService? = nil
    ) {
        self.database = database
        self.home = home
        self.mindfulness = mindfulness
        self.health = health
        self.rest = rest
        self.finance = finance
        self.insights = insights
        self.agent = agent
    }

    /// True when an LLM backend is configured for narrative generation.
    public var canNarrate: Bool { agent?.isAvailable() ?? false }

    /// Streams a warm weekly reflection from the digest, or nil if no backend.
    public func narrate(digest: [String]) -> AsyncThrowingStream<String, Error>? {
        agent?.weeklyNarrative(digest: digest)
    }

    public func load() async throws {
        reviews = try await database.writer.read { db in
            try Review.fetchAll(db, sql: "SELECT * FROM reviews ORDER BY createdAt DESC")
        }
    }

    public func save(_ review: Review) async throws {
        try await database.writer.write { db in try review.save(db) }
        reviews.removeAll { $0.id == review.id }
        reviews.insert(review, at: 0)
    }

    // MARK: - Weekly digest (N5)

    /// Factual, glanceable lines summarising the trailing 7 days.
    public func weeklyDigest(asOf now: Date = Date()) -> [String] {
        var lines: [String] = []
        let last7 = (0..<7).map { DayKey.make(now.addingTimeInterval(Double(-$0) * 86_400)) }

        let meditatedDays = last7.count { key in
            mindfulness.sessions.contains { $0.type != .focus && DayKey.make($0.date) == key }
        }
        if meditatedDays > 0 { lines.append("🧘 Meditated \(meditatedDays) of 7 days") }

        let focusMin = mindfulness.sessions
            .filter { $0.type == .focus && last7.contains(DayKey.make($0.date)) }
            .reduce(0) { $0 + $1.durationMinutes }
        if focusMin > 0 { lines.append("🎯 \(focusMin) min focused") }

        let workouts = health.thisWeekCount(asOf: now)
        if workouts > 0 { lines.append("🏋️ \(workouts) workout\(workouts == 1 ? "" : "s")") }

        let sleep = rest.avgHoursLast7(asOf: now)
        if sleep > 0 { lines.append(String(format: "😴 %.1fh average sleep", sleep)) }

        let moods = last7.compactMap { mindfulness.moods[$0] }
        if !moods.isEmpty {
            let avg = Double(moods.reduce(0, +)) / Double(moods.count)
            lines.append(String(format: "😊 Mood averaged %.1f/5", avg))
        }

        if let topSpend = finance.categorySpendingThisMonth(asOf: now).first {
            lines.append("💸 Most spending on \(topSpend.0.rawValue)")
        }

        if let insight = insights.topInsight {
            lines.append("💡 \(insight.phrase)")
        }

        return lines
    }

    /// ISO-week key like "2026-W27".
    public func weekKey(asOf now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let week = calendar.component(.weekOfYear, from: now)
        let year = calendar.component(.yearForWeekOfYear, from: now)
        return String(format: "%04d-W%02d", year, week)
    }

    // MARK: - Life Wheel (N6)

    /// Computed Life Score (0–100) per scored sphere.
    public func computedScores() -> [SphereType: Int] {
        Dictionary(uniqueKeysWithValues: home.scores.map {
            ($0.sphere, Int(($0.score * 100).rounded()))
        })
    }

    public func lifeWheelDeltas(selfRatings: [SphereType: Int]) -> [WheelDelta] {
        LifeWheel.deltas(selfRatings: selfRatings, computed: computedScores())
    }

    // MARK: - Persisting reviews

    @discardableResult
    public func saveWeekly(content: String, now: Date = Date()) async throws -> Review {
        let review = Review(
            id: Review.newID(now: now), type: .weekly,
            periodKey: weekKey(asOf: now), content: content, createdAt: now
        )
        try await save(review)
        return review
    }

    @discardableResult
    public func saveLifeWheel(
        selfRatings: [SphereType: Int], content: String, now: Date = Date()
    ) async throws -> Review {
        let ratings = Dictionary(uniqueKeysWithValues: selfRatings.map { ($0.key.rawValue, $0.value) })
        let review = Review(
            id: Review.newID(now: now), type: .lifeWheel,
            periodKey: quarterKey(asOf: now), content: content,
            selfRatings: ratings, createdAt: now
        )
        try await save(review)
        return review
    }

    /// Calendar quarter key like "2026-Q3".
    public func quarterKey(asOf now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        return "\(year)-Q\((month - 1) / 3 + 1)"
    }
}

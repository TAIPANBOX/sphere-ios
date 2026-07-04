import Foundation
import GRDB
import Observation

/// One day's predicted (pre-correction) readiness, kept so the engine can learn
/// how far our prediction sits from the user's felt energy.
struct ReadinessLogEntry: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "readiness_log"
    var dateKey: String
    var predicted: Int
    var createdAt: Date
}

/// Produces the adaptive "Today" verdict from Rest + Mindfulness + Health and
/// closes the self-correction loop against logged felt-energy.
@MainActor
@Observable
public final class ReadinessStore {
    private(set) var predictions: [String: Int] = [:]

    private let database: AppDatabase
    private let rest: RestStore
    private let mindfulness: MindfulnessStore
    private let health: HealthStore

    public init(
        database: AppDatabase, rest: RestStore, mindfulness: MindfulnessStore, health: HealthStore
    ) {
        self.database = database
        self.rest = rest
        self.mindfulness = mindfulness
        self.health = health
    }

    public func loadLedger() async throws {
        let rows = try await database.writer.read { db in
            try ReadinessLogEntry.fetchAll(db, sql: "SELECT * FROM readiness_log")
        }
        predictions = Dictionary(uniqueKeysWithValues: rows.map { ($0.dateKey, $0.predicted) })
    }

    // MARK: - Verdict

    private func input(asOf now: Date) -> ReadinessInput {
        ReadinessInput(
            sleepHours: lastNightSleep(asOf: now),
            sleepGoal: rest.schedule.goalHours,
            stress: mindfulness.todayStress(asOf: now),
            wakeHour: rest.schedule.wakeHour,
            bedtimeHour: rest.schedule.bedtimeHour,
            bedtimeMinute: rest.schedule.bedtimeMinute,
            correction: ReadinessEngine.correction(predicted: predictions, felt: health.energyLevels)
        )
    }

    public func verdict(asOf now: Date = Date()) -> ReadinessVerdict {
        ReadinessEngine.verdict(input(asOf: now))
    }

    /// Persists today's raw (pre-correction) prediction once per day, so
    /// tomorrow's correction can compare it against today's felt energy.
    public func recordPrediction(asOf now: Date = Date()) async {
        let key = DayKey.make(now)
        let raw = ReadinessEngine.rawScore(
            sleepHours: lastNightSleep(asOf: now),
            sleepGoal: rest.schedule.goalHours,
            stress: mindfulness.todayStress(asOf: now)
        )
        predictions[key] = raw
        let entry = ReadinessLogEntry(dateKey: key, predicted: raw, createdAt: now)
        try? await database.writer.write { db in try entry.save(db) }
    }

    public func todayEnergy(asOf now: Date = Date()) -> Int? { health.todayEnergy(asOf: now) }

    /// Logs how today actually felt (1–5) — the signal the correction learns from.
    public func rateEnergy(_ level: Int, asOf now: Date = Date()) async {
        try? await health.logEnergy(level, on: now)
    }

    private func lastNightSleep(asOf now: Date) -> Double? {
        rest.last7(asOf: now).max { $0.date < $1.date }?.hoursSlept
    }
}

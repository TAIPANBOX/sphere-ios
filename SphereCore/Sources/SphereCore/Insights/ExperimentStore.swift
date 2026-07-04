import Foundation
import GRDB
import Observation

/// Manages user-run N-of-1 experiments and analyses their cross-sphere effect
/// against the day-keyed metric series assembled by `InsightsStore`.
@MainActor
@Observable
public final class ExperimentStore {
    public private(set) var experiments: [Experiment] = []

    private let database: AppDatabase
    private let insights: InsightsStore

    public init(database: AppDatabase, insights: InsightsStore) {
        self.database = database
        self.insights = insights
    }

    public func load() async throws {
        experiments = try await database.writer.read { db in
            try Experiment.fetchAll(db, sql: "SELECT * FROM experiments ORDER BY createdAt DESC")
        }
    }

    public var running: [Experiment] { experiments.filter { $0.status == .running } }

    /// The running experiment to surface on Home — the one nearest completion.
    public func activeExperiment(asOf now: Date = Date()) -> Experiment? {
        running.max { $0.daysElapsed(asOf: now) < $1.daysElapsed(asOf: now) }
    }

    @discardableResult
    public func start(
        title: String, durationDays: Int, note: String = "",
        startDate: Date = Date(), now: Date = Date()
    ) async throws -> Experiment {
        let experiment = Experiment(
            id: Experiment.newID(now: now), title: title, note: note,
            startDate: startDate, durationDays: durationDays, status: .running, createdAt: now
        )
        try await save(experiment)
        return experiment
    }

    public func setStatus(_ experiment: Experiment, _ status: ExperimentStatus) async throws {
        var updated = experiment
        updated.status = status
        try await save(updated)
    }

    public func remove(_ experiment: Experiment) async throws {
        try await database.writer.write { db in _ = try experiment.delete(db) }
        experiments.removeAll { $0.id == experiment.id }
    }

    private func save(_ experiment: Experiment) async throws {
        try await database.writer.write { db in try experiment.save(db) }
        experiments.removeAll { $0.id == experiment.id }
        experiments.insert(experiment, at: 0)
        experiments.sort { $0.createdAt > $1.createdAt }
    }

    // MARK: - Analysis

    /// Measured effect of the experiment on every sufficiently-logged metric.
    public func analysis(for experiment: Experiment, asOf now: Date = Date()) -> [MetricEffect] {
        ExperimentEngine.analyze(
            series: insights.series(),
            startKey: DayKey.make(experiment.startDate),
            durationDays: experiment.durationDays,
            asOf: now
        )
    }

    public func headline(for experiment: Experiment, asOf now: Date = Date()) -> String? {
        ExperimentEngine.headline(analysis(for: experiment, asOf: now))
    }
}

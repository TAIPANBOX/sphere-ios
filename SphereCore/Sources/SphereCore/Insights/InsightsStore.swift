import Foundation
import Observation

/// Assembles day-keyed series from the sphere stores and runs the correlation
/// engine, exposing the "insight of the week". Recomputes on demand from the
/// already-loaded stores — cheap, and always fresh.
@MainActor
@Observable
public final class InsightsStore {
    private let health: HealthStore
    private let mindfulness: MindfulnessStore
    private let rest: RestStore
    private let finance: FinanceStore
    private let hobbies: HobbiesStore

    public init(
        health: HealthStore,
        mindfulness: MindfulnessStore,
        rest: RestStore,
        finance: FinanceStore,
        hobbies: HobbiesStore
    ) {
        self.health = health
        self.mindfulness = mindfulness
        self.rest = rest
        self.finance = finance
        self.hobbies = hobbies
    }

    /// The day-keyed metric series available for correlation. Only series with
    /// data are included.
    public func series() -> [DailySeries] {
        var result: [DailySeries] = []

        func add(_ id: String, _ name: String, _ values: [String: Double]) {
            if !values.isEmpty { result.append(DailySeries(metricID: id, displayName: name, values: values)) }
        }

        add("mood", "Mood", mindfulness.moods.mapValues(Double.init))
        add("stress", "Stress", mindfulness.stress.mapValues(Double.init))
        add("energy", "Energy", health.energyLevels.mapValues(Double.init))
        add("meal", "Meal quality", health.mealQuality.mapValues(Double.init))
        add("sleep", "Sleep", sumByDay(rest.sleepEntries.map { ($0.date, $0.hoursSlept) }))
        add("spend", "Spending", sumByDay(
            finance.transactions.filter { $0.type == .expense }.map { ($0.date, $0.amount) }
        ))
        add("meditation", "Meditation", sumByDay(
            // Exclude focus/deep-work sessions, matching `hasMeditated` and the
            // rest of the app, so the series tracks actual meditation.
            mindfulness.sessions
                .filter { $0.type != .focus }
                .map { ($0.date, Double($0.durationMinutes)) }
        ))
        add("workouts", "Workout time", sumByDay(
            health.workouts.map { ($0.date, Double($0.durationMinutes)) }
        ))
        add("hobby", "Hobby time", sumByDay(
            hobbies.sessions.map { ($0.date, Double($0.durationMinutes)) }
        ))

        return result
    }

    /// The strongest cross-sphere relationships worth surfacing.
    public func weeklyInsights(limit: Int = 3) -> [Correlation] {
        Array(CorrelationEngine.correlations(series()).prefix(limit))
    }

    public var topInsight: Correlation? {
        weeklyInsights(limit: 1).first
    }

    private func sumByDay(_ samples: [(Date, Double)]) -> [String: Double] {
        var byDay: [String: Double] = [:]
        for (date, value) in samples {
            byDay[DayKey.make(date), default: 0] += value
        }
        return byDay
    }
}

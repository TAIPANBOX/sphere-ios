import Foundation

public struct SphereScore: Sendable, Equatable, Identifiable {
    public let sphere: SphereType
    public let emoji: String
    /// 0–1
    public let score: Double
    public let insight: String

    public var id: SphereType { sphere }

    public init(sphere: SphereType, emoji: String, score: Double, insight: String) {
        self.sphere = sphere
        self.emoji = emoji
        self.score = score
        self.insight = insight
    }
}

/// Life Score formulas ported from the Flutter home tab (`_computeScores`).
/// Covers the wave-1 spheres; wave-2 spheres (relationships, rest, hobbies)
/// join here when their stores are ported — until then the overall score is
/// the mean of what exists.
public enum LifeScore {
    public static func compute(
        metrics: HealthMetrics?,
        books: [Book],
        careerTasks: [CareerTask],
        totalIncome: Double,
        totalExpenses: Double,
        goals: [Goal],
        now: Date = Date()
    ) -> [SphereScore] {
        [
            health(metrics: metrics),
            learning(books: books),
            career(tasks: careerTasks, now: now),
            finance(totalIncome: totalIncome, totalExpenses: totalExpenses),
            goalsScore(goals: goals),
        ]
    }

    public static func overall(_ scores: [SphereScore]) -> Double {
        guard !scores.isEmpty else { return 0 }
        return scores.map(\.score).reduce(0, +) / Double(scores.count)
    }

    public static func best(_ scores: [SphereScore]) -> SphereScore? {
        scores.max { $0.score < $1.score }
    }

    public static func needsFocus(_ scores: [SphereScore]) -> SphereScore? {
        scores.min { $0.score < $1.score }
    }

    // MARK: - Per-sphere formulas (weights match the Dart implementation)

    static func health(metrics: HealthMetrics?) -> SphereScore {
        guard let metrics else {
            return SphereScore(
                sphere: .health, emoji: "🫀", score: 0.75,
                insight: "Connect Apple Health to see live stats"
            )
        }
        let stepsScore = min(max(Double(metrics.steps) / 10_000, 0), 1)
        let sleepScore = min(max(metrics.sleepHours / 8, 0), 1)
        let stepsLabel = metrics.steps >= 1_000
            ? String(format: "%.1fk", Double(metrics.steps) / 1_000)
            : "\(metrics.steps)"
        let hours = Int(metrics.sleepHours)
        let minutes = Int((metrics.sleepHours - Double(hours)) * 60)
        let sleepLabel = minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        return SphereScore(
            sphere: .health, emoji: "🫀",
            score: stepsScore * 0.6 + sleepScore * 0.4,
            insight: "\(stepsLabel) steps · \(sleepLabel) sleep"
        )
    }

    static func learning(books: [Book]) -> SphereScore {
        guard !books.isEmpty else {
            return SphereScore(
                sphere: .learning, emoji: "📚", score: 0.5,
                insight: "Add a book or course to start"
            )
        }
        let reading = books.count { $0.status == .reading }
        return SphereScore(
            sphere: .learning, emoji: "📚", score: 0.6,
            insight: "\(reading) reading · \(books.count) in library"
        )
    }

    static func career(tasks: [CareerTask], now: Date = Date()) -> SphereScore {
        guard !tasks.isEmpty else {
            return SphereScore(
                sphere: .career, emoji: "💼", score: 0.85,
                insight: "No tasks tracked yet"
            )
        }
        let open = tasks.count { $0.status != .done }
        let overdue = tasks.count { $0.isOverdue(asOf: now) }
        let done = tasks.count { $0.status == .done }
        let score = min(max(
            Double(done) / Double(tasks.count) * 0.6 + (overdue == 0 ? 1.0 : 0.4) * 0.4,
            0.2
        ), 1)
        let insight = if overdue > 0 {
            "\(open) open · \(overdue) overdue"
        } else if open == 0 {
            "All tasks done 🎉"
        } else {
            "\(open) open tasks on track"
        }
        return SphereScore(sphere: .career, emoji: "💼", score: score, insight: insight)
    }

    static func finance(totalIncome: Double, totalExpenses: Double) -> SphereScore {
        guard totalIncome > 0 else {
            return SphereScore(
                sphere: .finance, emoji: "💰", score: 0.5,
                insight: "Log income and spending to see trends"
            )
        }
        let rate = min(max((totalIncome - totalExpenses) / totalIncome, 0), 1)
        let score = min(max(0.3 + rate * 0.7, 0), 1)
        let insight = totalIncome - totalExpenses >= 0
            ? "Saving \(Int((rate * 100).rounded()))% of income"
            : "Spending exceeds income"
        return SphereScore(sphere: .finance, emoji: "💰", score: score, insight: insight)
    }

    static func goalsScore(goals: [Goal]) -> SphereScore {
        let active = goals.filter { $0.status == .active }
        guard !active.isEmpty else {
            return SphereScore(
                sphere: .goals, emoji: "🎯", score: 0.5,
                insight: "Set a goal to get moving"
            )
        }
        let average = active.map(\.progressPercent).reduce(0, +) / active.count
        return SphereScore(
            sphere: .goals, emoji: "🎯",
            score: min(max(Double(average) / 100, 0.1), 1),
            insight: "\(active.count) active · \(average)% avg progress"
        )
    }
}

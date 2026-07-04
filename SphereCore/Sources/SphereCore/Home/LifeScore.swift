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
/// Eight scored spheres, in the Dart display order.
public enum LifeScore {
    public static func compute(
        metrics: HealthMetrics?,
        books: [Book],
        careerTasks: [CareerTask],
        totalIncome: Double,
        totalExpenses: Double,
        goals: [Goal],
        contacts: [Contact] = [],
        avgSleepHours: Double = 0,
        avgRecovery: RecoveryLevel = .good,
        hobbiesCount: Int = 0,
        hobbiesWeeklyMinutes: Int = 0,
        now: Date = Date()
    ) -> [SphereScore] {
        [
            health(metrics: metrics),
            learning(books: books),
            career(tasks: careerTasks, now: now),
            finance(totalIncome: totalIncome, totalExpenses: totalExpenses),
            relationships(contacts: contacts, now: now),
            rest(avgSleepHours: avgSleepHours, avgRecovery: avgRecovery),
            hobbies(count: hobbiesCount, weeklyMinutes: hobbiesWeeklyMinutes),
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

    static func relationships(contacts: [Contact], now: Date = Date()) -> SphereScore {
        guard !contacts.isEmpty else {
            return SphereScore(
                sphere: .relationships, emoji: "💜", score: 0.75,
                insight: "Add people you want to stay close to"
            )
        }
        let checkin = contacts.count { $0.needsCheckin(asOf: now) }
        let birthdays = contacts.count { ($0.daysUntilBirthday(asOf: now) ?? 999) <= 30 }
        let score = checkin == 0
            ? 0.9
            : min(max(1.0 - Double(checkin) / Double(contacts.count) * 0.5, 0.3), 0.9)
        let insight = if birthdays > 0 {
            "\(contacts.count) people · \(birthdays) birthday\(birthdays == 1 ? "" : "s") coming up"
        } else if checkin > 0 {
            "\(contacts.count) people · \(checkin) need a check-in"
        } else {
            "\(contacts.count) people · all caught up"
        }
        return SphereScore(sphere: .relationships, emoji: "💜", score: score, insight: insight)
    }

    static func rest(avgSleepHours: Double, avgRecovery: RecoveryLevel) -> SphereScore {
        guard avgSleepHours > 0 else {
            return SphereScore(
                sphere: .rest, emoji: "🌊", score: 0.5,
                insight: "Log sleep to see recovery"
            )
        }
        return SphereScore(
            sphere: .rest, emoji: "🌊",
            score: min(max(avgSleepHours / 8, 0.2), 1),
            insight: String(format: "%.1fh avg sleep · %@ recovery", avgSleepHours, avgRecovery.label)
        )
    }

    static func hobbies(count: Int, weeklyMinutes: Int) -> SphereScore {
        guard count > 0 else {
            return SphereScore(
                sphere: .hobbies, emoji: "🎸", score: 0.5,
                insight: "Add a hobby to make time for it"
            )
        }
        let insight = weeklyMinutes > 0
            ? "\(count) hobbies · \(weeklyMinutes) min this week"
            : "\(count) hobbies · no time logged this week"
        return SphereScore(
            sphere: .hobbies, emoji: "🎸",
            score: min(max(Double(weeklyMinutes) / 300, 0.1), 1),
            insight: insight
        )
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

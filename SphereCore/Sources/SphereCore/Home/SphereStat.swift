import Foundation

/// One line of live summary + a 0–1 progress value for a sphere card on the
/// grid. The eight scored spheres reuse their ``LifeScore`` insight/score;
/// the four unscored ones (travel, mindfulness, creativity, home) are
/// summarized here so every card has a stat without duplicating LifeScore.
public struct SphereStat: Sendable, Equatable {
    public let statLine: String
    /// 0–1, drives the card's progress bar.
    public let progress: Double

    public init(statLine: String, progress: Double) {
        self.statLine = statLine
        self.progress = progress
    }

    public static func travel(
        upcomingTrip: (destination: String, daysUntil: Int)?,
        visitedCount: Int
    ) -> SphereStat {
        if let trip = upcomingTrip {
            return SphereStat(
                statLine: "\(trip.destination) in \(trip.daysUntil) d",
                progress: 0.8
            )
        }
        return SphereStat(
            statLine: visitedCount > 0 ? "\(visitedCount) countries visited" : "No trips planned",
            progress: visitedCount > 0 ? 0.5 : 0.2
        )
    }

    public static func mindfulness(streakDays: Int, todayMood: Int?) -> SphereStat {
        var parts: [String] = []
        if streakDays > 0 { parts.append("\(streakDays)-day streak") }
        if let mood = todayMood { parts.append("mood \(mood)/5") }
        return SphereStat(
            statLine: parts.isEmpty ? "Check in with yourself" : parts.joined(separator: " · "),
            progress: min(max(Double(streakDays) / 7, 0.1), 1)
        )
    }

    public static func creativity(inProgressCount: Int, avgProgress: Int) -> SphereStat {
        SphereStat(
            statLine: inProgressCount > 0
                ? "\(inProgressCount) active · \(avgProgress)% avg"
                : "Capture an idea",
            progress: inProgressCount > 0 ? Double(avgProgress) / 100 : 0.2
        )
    }

    public static func home(openTasks: Int, thirstyPlants: Int) -> SphereStat {
        var parts: [String] = []
        if openTasks > 0 { parts.append("\(openTasks) task\(openTasks == 1 ? "" : "s")") }
        if thirstyPlants > 0 { parts.append("\(thirstyPlants) plant\(thirstyPlants == 1 ? "" : "s") thirsty") }
        return SphereStat(
            statLine: parts.isEmpty ? "All tidy" : parts.joined(separator: " · "),
            progress: parts.isEmpty ? 0.9 : 0.5
        )
    }
}

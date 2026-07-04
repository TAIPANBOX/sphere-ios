import Foundation
import Observation

/// Gathers the year's cross-sphere totals for the "Year in Sphere" recap.
@MainActor
@Observable
public final class RecapStore {
    private let mindfulness: MindfulnessStore
    private let health: HealthStore
    private let learning: LearningStore
    private let travel: TravelStore
    private let goals: GoalsStore
    private let creativity: CreativityStore
    private let hobbies: HobbiesStore

    public init(
        mindfulness: MindfulnessStore, health: HealthStore, learning: LearningStore,
        travel: TravelStore, goals: GoalsStore, creativity: CreativityStore, hobbies: HobbiesStore
    ) {
        self.mindfulness = mindfulness
        self.health = health
        self.learning = learning
        self.travel = travel
        self.goals = goals
        self.creativity = creativity
        self.hobbies = hobbies
    }

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    private func isIn(_ year: Int, _ date: Date) -> Bool {
        Self.calendar.component(.year, from: date) == year
    }

    public func stats(year: Int) -> RecapStats {
        let meditation = mindfulness.sessions.filter { $0.type != .focus && isIn(year, $0.date) }
        let focus = mindfulness.sessions.filter { $0.type == .focus && isIn(year, $0.date) }

        return RecapStats(
            year: year,
            meditationMinutes: meditation.reduce(0) { $0 + $1.durationMinutes },
            focusMinutes: focus.reduce(0) { $0 + $1.durationMinutes },
            workouts: health.workouts.count { isIn(year, $0.date) },
            countriesVisited: travel.visited.count { $0.year == year },
            journalEntries: mindfulness.journal.count { isIn(year, $0.date) },
            gratitudeNotes: mindfulness.gratitude.count { isIn(year, $0.date) },
            creativeMinutes: creativity.sessions.filter { isIn(year, $0.date) }.reduce(0) { $0 + $1.minutes },
            hobbyMinutes: hobbies.sessions.filter { isIn(year, $0.date) }.reduce(0) { $0 + $1.durationMinutes }
        )
    }

    public func cards(year: Int) -> [RecapCard] { YearInSphere.cards(from: stats(year: year)) }

    public func currentYear(now: Date = Date()) -> Int {
        Self.calendar.component(.year, from: now)
    }
}

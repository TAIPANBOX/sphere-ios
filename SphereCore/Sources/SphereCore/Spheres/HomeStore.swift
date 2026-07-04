import Foundation
import Observation

/// Home-tab aggregator: weather, the streamed Meta Agent summary, Life Score
/// across ported spheres, and the Today's Focus feed. Reads from the sphere
/// stores wired at the composition root.
@MainActor
@Observable
public final class HomeStore {
    public enum BriefState: Equatable {
        case idle
        case streaming
        case done
        case failed(String)
    }

    public private(set) var weather: Weather?
    public private(set) var briefText = ""
    public private(set) var briefState = BriefState.idle
    /// True when the brief failed purely because no provider key is set, so
    /// the UI can turn the Meta Agent card into a "configure provider" CTA
    /// instead of an inert error line.
    public private(set) var briefNeedsProviderKey = false
    public private(set) var insight: AgentInsight?

    private let health: HealthStore
    private let learning: LearningStore
    private let career: CareerStore
    private let finance: FinanceStore
    private let goals: GoalsStore
    private let rest: RestStore?
    private let hobbies: HobbiesStore?
    private let mindfulness: MindfulnessStore?
    private let relationships: RelationshipsStore?
    private let homeSphere: HomeSphereStore?
    private let agent: AgentService?
    private let weatherService: WeatherService?
    private let location: (any LocationProviding)?
    private let calendarProvider: (any CalendarProviding)?

    /// Today's calendar events, populated by `refreshCalendar()`.
    public private(set) var todayEvents: [CalendarEvent] = []
    public var hasCalendarProvider: Bool { calendarProvider != nil }

    public init(
        health: HealthStore,
        learning: LearningStore,
        career: CareerStore,
        finance: FinanceStore,
        goals: GoalsStore,
        rest: RestStore? = nil,
        hobbies: HobbiesStore? = nil,
        mindfulness: MindfulnessStore? = nil,
        relationships: RelationshipsStore? = nil,
        homeSphere: HomeSphereStore? = nil,
        agent: AgentService? = nil,
        weatherService: WeatherService? = nil,
        location: (any LocationProviding)? = nil,
        calendarProvider: (any CalendarProviding)? = nil
    ) {
        self.health = health
        self.learning = learning
        self.career = career
        self.finance = finance
        self.goals = goals
        self.rest = rest
        self.hobbies = hobbies
        self.mindfulness = mindfulness
        self.relationships = relationships
        self.homeSphere = homeSphere
        self.agent = agent
        self.weatherService = weatherService
        self.location = location
        self.calendarProvider = calendarProvider
    }

    // MARK: - Derived state

    public var scores: [SphereScore] {
        LifeScore.compute(
            metrics: health.metricsAvailable ? health.metrics : nil,
            books: learning.books,
            careerTasks: career.tasks,
            totalIncome: finance.totalIncome,
            totalExpenses: finance.totalExpenses,
            goals: goals.goals,
            contacts: relationships?.contacts ?? [],
            avgSleepHours: rest?.avgHoursLast7() ?? 0,
            avgRecovery: rest?.avgRecoveryLast7() ?? .good,
            hobbiesCount: hobbies?.hobbies.count ?? 0,
            hobbiesWeeklyMinutes: hobbies?.totalWeeklyMinutes() ?? 0
        )
    }

    /// 0–100
    public var lifeScore: Int {
        Int((LifeScore.overall(scores) * 100).rounded())
    }

    public var bestSphere: SphereScore? {
        LifeScore.best(scores)
    }

    public var needsFocusSphere: SphereScore? {
        LifeScore.needsFocus(scores)
    }

    /// Sick/vacation mode — set by the app from the profile. Suppresses the
    /// daily-habit nags in Today's Focus and shows a "paused" badge on Home.
    public var isPaused = false

    /// What the user actually logged today, for the evening ritual review.
    public func todayHighlights(asOf now: Date = Date()) -> [String] {
        let today = DayKey.make(now)
        var lines: [String] = []
        if health.waterToday > 0 {
            lines.append("💧 \(health.waterToday) glass\(health.waterToday == 1 ? "" : "es") of water")
        }
        if let energy = health.todayEnergy(asOf: now) { lines.append("⚡ Energy \(energy)/5") }
        let workouts = health.workouts.count { DayKey.make($0.date) == today }
        if workouts > 0 { lines.append("🏋️ \(workouts) workout\(workouts == 1 ? "" : "s")") }
        if mindfulness?.hasMeditated(on: now) == true { lines.append("🧘 Meditated") }
        if let mood = mindfulness?.todaysMood(asOf: now) { lines.append("😊 Mood \(mood)/5") }
        let gratitude = mindfulness?.gratitude.count { DayKey.make($0.date) == today } ?? 0
        if gratitude > 0 { lines.append("🙏 \(gratitude) gratitude note\(gratitude == 1 ? "" : "s")") }
        return lines
    }

    public var focusItems: [FocusItem] {
        FocusBuilder.build(
            careerTasks: career.tasks,
            goals: goals.goals,
            metrics: health.metricsAvailable ? health.metrics : nil,
            contacts: relationships?.contacts ?? [],
            homeTasks: homeSphere?.tasks ?? [],
            hasMeditatedToday: mindfulness?.hasMeditated() ?? false,
            isPaused: isPaused
        )
    }

    // MARK: - Loading

    public func refreshWeather() async {
        guard let weatherService, let location else { return }
        do {
            let coordinates = try await location.currentLocation()
            weather = try await weatherService.current(at: coordinates)
        } catch {
            // Weather is decorative; keep the last known value on failure.
        }
    }

    /// Fetches today's calendar events (requesting access on first use).
    public func refreshCalendar(now: Date = Date()) async {
        guard let calendarProvider else { return }
        guard await calendarProvider.requestAccess() else { return }
        let dayStart = Calendar.current.startOfDay(for: now)
        let dayEnd = dayStart.addingTimeInterval(86_400)
        let events = await calendarProvider.events(from: dayStart, to: dayEnd)
        todayEvents = CalendarContext.today(events, now: now)
    }

    /// Streams the Meta Agent morning brief into `briefText`. When no context is
    /// passed, today's calendar events are folded in automatically.
    public func streamBrief(calendarContext: String = "") async {
        guard let agent, briefState != .streaming else { return }
        let context = calendarContext.isEmpty
            ? CalendarContext.summary(todayEvents)
            : calendarContext
        briefState = .streaming
        briefNeedsProviderKey = false
        briefText = ""
        do {
            for try await chunk in agent.brief(calendarContext: context) {
                briefText += chunk
            }
            briefState = .done
        } catch let error as AgentError {
            if case .noApiKey = error { briefNeedsProviderKey = true }
            briefState = .failed(Self.message(for: error))
        } catch {
            briefState = .failed("\(error)")
        }
    }

    public func loadInsight() async {
        guard let agent else { return }
        insight = try? await agent.insight()
    }

    private static func message(for error: AgentError) -> String {
        switch error {
        case .noApiKey: "Add an AI provider key in Settings to get your brief."
        case .backendUnavailable: "Offline — reconnect to refresh your brief."
        case .api(let message): message
        }
    }
}

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
    public private(set) var insight: AgentInsight?

    private let health: HealthStore
    private let learning: LearningStore
    private let career: CareerStore
    private let finance: FinanceStore
    private let goals: GoalsStore
    private let agent: AgentService?
    private let weatherService: WeatherService?
    private let location: (any LocationProviding)?

    public init(
        health: HealthStore,
        learning: LearningStore,
        career: CareerStore,
        finance: FinanceStore,
        goals: GoalsStore,
        agent: AgentService? = nil,
        weatherService: WeatherService? = nil,
        location: (any LocationProviding)? = nil
    ) {
        self.health = health
        self.learning = learning
        self.career = career
        self.finance = finance
        self.goals = goals
        self.agent = agent
        self.weatherService = weatherService
        self.location = location
    }

    // MARK: - Derived state

    public var scores: [SphereScore] {
        LifeScore.compute(
            metrics: health.metricsAvailable ? health.metrics : nil,
            books: learning.books,
            careerTasks: career.tasks,
            totalIncome: finance.totalIncome,
            totalExpenses: finance.totalExpenses,
            goals: goals.goals
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

    public var focusItems: [FocusItem] {
        FocusBuilder.build(
            careerTasks: career.tasks,
            goals: goals.goals,
            metrics: health.metricsAvailable ? health.metrics : nil
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

    /// Streams the Meta Agent morning brief into `briefText`.
    public func streamBrief(calendarContext: String = "") async {
        guard let agent, briefState != .streaming else { return }
        briefState = .streaming
        briefText = ""
        do {
            for try await chunk in agent.brief(calendarContext: calendarContext) {
                briefText += chunk
            }
            briefState = .done
        } catch let error as AgentError {
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

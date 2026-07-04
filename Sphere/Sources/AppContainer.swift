import Foundation
import SphereCore
import WidgetKit

/// Composition root: builds the databases, services, and one store per
/// sphere, and wires the cross-sphere connections the stores expose as
/// parameters (see docs/HANDOFF.md "What's next").
@MainActor
@Observable
final class AppContainer {
    let database: AppDatabase
    let engram: EngramStore
    let keyStore: KeychainAPIKeyStore
    let agent: AgentService

    let goals: GoalsStore
    let health: HealthStore
    let finance: FinanceStore
    let learning: LearningStore
    let career: CareerStore
    let rest: RestStore
    let travel: TravelStore
    let mindfulness: MindfulnessStore
    let homeSphere: HomeSphereStore
    let creativity: CreativityStore
    let hobbies: HobbiesStore
    let relationships: RelationshipsStore

    let profile: ProfileStore
    let toolRegistry: SphereToolRegistry
    let home: HomeStore

    private var chatSessions: [String: ChatSession] = [:]

    init() {
        let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("Sphere", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

        // Fail-fast by design: if local storage cannot open, the app has
        // nothing meaningful to show.
        database = try! AppDatabase(path: supportDir.appendingPathComponent("sphere.db").path)
        engram = try! EngramStore(path: supportDir.appendingPathComponent("sphere.engram.db").path)

        keyStore = KeychainAPIKeyStore()
        let cache = FileOfflineCache(directory: supportDir.appendingPathComponent("cache"))
        agent = AgentService(keyStore: keyStore, engram: engram, cache: cache)

        goals = GoalsStore(database: database, engram: engram)
        health = HealthStore(
            database: database, engram: engram, metricsProvider: HealthKitService()
        )
        finance = FinanceStore(database: database, engram: engram)
        learning = LearningStore(database: database, engram: engram)
        career = CareerStore(database: database, engram: engram)
        rest = RestStore(database: database, engram: engram)
        travel = TravelStore(database: database, engram: engram)
        mindfulness = MindfulnessStore(database: database, engram: engram)
        homeSphere = HomeSphereStore(database: database, engram: engram)
        creativity = CreativityStore(database: database, engram: engram)
        hobbies = HobbiesStore(database: database, engram: engram)
        relationships = RelationshipsStore(database: database, engram: engram)
        profile = ProfileStore(database: database)

        toolRegistry = SphereToolRegistry(tools:
            goals.tools + health.tools + finance.tools + learning.tools
                + career.tools + rest.tools + travel.tools + mindfulness.tools
                + homeSphere.tools + creativity.tools + hobbies.tools
                + relationships.tools
        )

        home = HomeStore(
            health: health,
            learning: learning,
            career: career,
            finance: finance,
            goals: goals,
            rest: rest,
            hobbies: hobbies,
            mindfulness: mindfulness,
            relationships: relationships,
            homeSphere: homeSphere,
            agent: agent,
            weatherService: WeatherService(),
            location: CoreLocationProvider()
        )
    }

    /// Loads every sphere store once at launch so grids, Life Score, and
    /// agent lookup tools see data without visiting each screen first.
    func loadAll() async {
        try? await profile.load()
        try? await goals.load()
        try? await health.load()
        try? await finance.load()
        try? await learning.load()
        try? await career.load()
        try? await rest.load()
        try? await travel.load()
        try? await mindfulness.load()
        try? await homeSphere.load()
        try? await creativity.load()
        try? await hobbies.load()
        try? await relationships.load()
        await BirthdayReminders.sync(contacts: relationships.contacts)
        refreshWidget()
    }

    /// Call after contact mutations so reminders track the latest birthdays.
    func refreshBirthdayReminders() async {
        await BirthdayReminders.sync(contacts: relationships.contacts)
    }

    /// One conversation per sphere, kept alive for the app session. Name and
    /// profile context are refreshed on each open so profile edits take
    /// effect without restarting the session.
    func chatSession(for sphere: SphereType) -> ChatSession {
        let session = chatSessions[sphere.rawValue] ?? {
            let created = ChatSession(
                sphereName: sphere.rawValue.capitalized,
                sphereType: sphere,
                agent: agent,
                tools: toolRegistry
            )
            chatSessions[sphere.rawValue] = created
            return created
        }()
        session.userName = profile.profile.name
        session.userContext = profile.agentContext
        return session
    }

    /// Live one-line summary + progress for a sphere card. Reuses the
    /// LifeScore insight/score for the eight scored spheres; computes the
    /// other four from their stores.
    func sphereStat(for sphere: SphereType) -> SphereStat {
        if let score = home.scores.first(where: { $0.sphere == sphere }) {
            return SphereStat(statLine: score.insight, progress: score.score)
        }
        switch sphere {
        case .travel:
            let next = travel.nextTrip()
            return .travel(
                upcomingTrip: next.flatMap { trip in trip.daysUntil().map { (trip.destination, $0) } },
                visitedCount: travel.visited.count
            )
        case .mindfulness:
            return .mindfulness(
                streakDays: mindfulness.currentStreak(),
                todayMood: mindfulness.todaysMood()
            )
        case .creativity:
            let active = creativity.inProgress
            let avg = active.isEmpty ? 0 : active.map(\.progressPercent).reduce(0, +) / active.count
            return .creativity(inProgressCount: active.count, avgProgress: avg)
        case .home:
            return .home(
                openTasks: homeSphere.openTasks.count,
                thirstyPlants: homeSphere.needsWateringCount()
            )
        default:
            return SphereStat(statLine: "", progress: 0.5)
        }
    }

    /// Persists a reordered sphere list from a drag-to-reorder gesture.
    func reorderSpheres(_ spheres: [SphereType]) async {
        try? await profile.setSphereOrder(spheres)
    }

    /// Nightly-ish Engram maintenance; call on app background.
    func runMemoryMaintenance() async {
        _ = try? await engram.runDecay()
        _ = try? await engram.prune()
    }

    /// Writes the home-screen widget snapshot (Life Score, best/needs-focus
    /// sphere, top focus items) to the shared App Group and reloads the
    /// widget timeline. Cheap; call after loadAll and on background.
    func refreshWidget() {
        guard let store = WidgetSnapshotStore.shared() else { return }
        let scores = home.scores
        guard let best = LifeScore.best(scores), let needs = LifeScore.needsFocus(scores) else { return }
        let snapshot = WidgetSnapshot(
            lifeScore: home.lifeScore,
            bestEmoji: best.emoji,
            bestName: best.sphere.rawValue.capitalized,
            needsFocusEmoji: needs.emoji,
            needsFocusName: needs.sphere.rawValue.capitalized,
            topFocus: home.focusItems.prefix(3).map {
                WidgetSnapshot.FocusLine(emoji: $0.emoji, title: $0.title)
            },
            updatedAt: Date()
        )
        store.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

import Foundation
import SphereCore

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
            agent: agent,
            weatherService: WeatherService(),
            location: CoreLocationProvider()
        )
    }

    /// Loads every sphere store once at launch so grids, Life Score, and
    /// agent lookup tools see data without visiting each screen first.
    func loadAll() async {
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
    }

    /// One conversation per sphere, kept alive for the app session.
    func chatSession(for sphere: SphereType, userName: String) -> ChatSession {
        if let existing = chatSessions[sphere.rawValue] {
            existing.userName = userName
            return existing
        }
        let session = ChatSession(
            sphereName: sphere.rawValue.capitalized,
            sphereType: sphere,
            agent: agent,
            tools: toolRegistry,
            userName: userName
        )
        chatSessions[sphere.rawValue] = session
        return session
    }

    /// Nightly-ish Engram maintenance; call on app background.
    func runMemoryMaintenance() async {
        _ = try? await engram.runDecay()
        _ = try? await engram.prune()
    }
}

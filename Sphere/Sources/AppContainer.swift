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
    let ritual: RitualStore
    let insights: InsightsStore
    let nudges: NudgeStore
    let reviews: ReviewStore
    let experiments: ExperimentStore
    let readiness: ReadinessStore
    let search: SearchStore
    let models: ModelManager
    let recap: RecapStore
    let cloudModels: OpenRouterModelCatalog

    private var chatSessions: [String: ChatSession] = [:]

    init() {
        // Databases live in the App Group container (shared with the widget /
        // App Intents / watch), migrated from the legacy Application Support
        // path on first run. Falls back to Application Support when there is
        // no App Group entitlement (unsigned / CI).
        let dbDir = DatabaseLocation.resolve()

        // Fail-fast by design: if local storage cannot open, the app has
        // nothing meaningful to show.
        database = try! AppDatabase(path: dbDir.appendingPathComponent("sphere.db").path)
        engram = try! EngramStore(path: dbDir.appendingPathComponent("sphere.engram.db").path)

        keyStore = KeychainAPIKeyStore()
        let cache = FileOfflineCache(directory: dbDir.appendingPathComponent("cache"))
        agent = AgentService(
            keyStore: keyStore,
            engram: engram,
            cache: cache,
            engineFactory: { provider in
                // Nonisolated read: the chosen cloud model id lives in
                // UserDefaults, so no MainActor state is touched here. Called
                // on every resolution so a Settings change is picked up
                // without restarting the app.
                provider.makeEngine(model: CloudModelPreference.current)
            },
            onDeviceEngine: { OnDeviceAI.makeEngineIfAvailable() },
            localModelEngine: {
                // Nonisolated read: the active choice lives in UserDefaults and
                // installation is a marker file, so no MainActor state is touched.
                guard let id = UserDefaults.standard.string(forKey: Prefs.activeModel),
                      let model = ModelCatalog.model(id: id),
                      LocalModelAI.isInstalled(model)
                else { return nil }
                return LocalModelAI.makeEngine(hubID: model.hubID)
            },
            preferredBackend: { AppBackendPreference.current }
        )

        goals = GoalsStore(database: database, engram: engram)
        let healthKit = HealthKitService()
        health = HealthStore(
            database: database, engram: engram, metricsProvider: healthKit
        )
        finance = FinanceStore(database: database, engram: engram)
        learning = LearningStore(database: database, engram: engram)
        career = CareerStore(database: database, engram: engram)
        rest = RestStore(database: database, engram: engram, metricsProvider: healthKit)
        travel = TravelStore(database: database, engram: engram, photoStore: TripPhotoStorage())
        mindfulness = MindfulnessStore(database: database, engram: engram)
        homeSphere = HomeSphereStore(database: database, engram: engram)
        creativity = CreativityStore(database: database, engram: engram)
        hobbies = HobbiesStore(database: database, engram: engram)
        relationships = RelationshipsStore(
            database: database, engram: engram, contactsProvider: ContactsService()
        )
        profile = ProfileStore(database: database)
        ritual = RitualStore(database: database)
        insights = InsightsStore(
            health: health, mindfulness: mindfulness, rest: rest,
            finance: finance, hobbies: hobbies
        )
        nudges = NudgeStore(
            database: database, mindfulness: mindfulness, finance: finance,
            career: career, homeSphere: homeSphere, rest: rest
        )

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
            location: CoreLocationProvider(),
            calendarProvider: EventKitService()
        )
        reviews = ReviewStore(
            database: database, home: home, mindfulness: mindfulness,
            health: health, rest: rest, finance: finance, insights: insights, agent: agent
        )
        experiments = ExperimentStore(database: database, insights: insights)
        readiness = ReadinessStore(
            database: database, rest: rest, mindfulness: mindfulness, health: health
        )
        models = ModelManager(
            // MLX-backed downloader on device (real Hub download with progress);
            // URLSession fallback keeps the simulator/UI path working.
            downloader: LocalModelAI.makeDownloader() ?? ModelDownloadService(),
            preferences: ModelPreferences()
        )
        recap = RecapStore(
            mindfulness: mindfulness, health: health, learning: learning,
            travel: travel, goals: goals, creativity: creativity, hobbies: hobbies
        )
        let appSupportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sphere", isDirectory: true)
        cloudModels = OpenRouterModelCatalog(cacheDirectory: appSupportDir.appendingPathComponent("cache"))
        search = SearchStore(
            goals: goals, health: health, finance: finance, learning: learning,
            career: career, relationships: relationships, homeSphere: homeSphere,
            travel: travel, hobbies: hobbies, creativity: creativity,
            mindfulness: mindfulness, engram: engram
        )

        WatchBridge.shared.onCommand = { [weak self] command in
            Task { @MainActor in await self?.apply(command) }
        }
    }

    /// Loads every sphere store once at launch so grids, Life Score, and
    /// agent lookup tools see data without visiting each screen first.
    func loadAll() async {
        try? await profile.load()
        try? await ritual.load()
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
        applyWellbeing()
        try? await nudges.loadLedger()
        nudges.refresh()
        try? await reviews.load()
        try? await experiments.load()
        try? await readiness.loadLedger()
        await readiness.recordPrediction()
        await syncReminders()
        refreshWidget()
    }

    /// Builds every opted-in reminder category from live store data and syncs
    /// them in one idempotent pass. Managing all categories in a single call
    /// means a category turned off has its pending notifications cleared too.
    func syncReminders(asOf now: Date = Date()) async {
        let p = profile.profile
        func on(_ category: NotificationCategory) -> Bool {
            p.notificationEnabled(category.rawValue, default: category.defaultOn)
        }

        var plans: [NotificationPlan] = []
        if on(.birthday) {
            plans += NotificationPlanBuilder.birthdays(relationships.contacts.filter { $0.birthday != nil })
        }
        if on(.habit) {
            plans += NotificationPlanBuilder.habitReminders(goals.habits)
        }
        if on(.water) {
            plans += NotificationPlanBuilder.waterReminders()
        }
        if on(.medication) {
            plans += NotificationPlanBuilder.medicationReminders(health.medications)
        }
        if on(.bedtime), let bed = NotificationPlanBuilder.bedtime(rest.schedule) {
            plans.append(bed)
        }
        if on(.plant) {
            plans += NotificationPlanBuilder.plantWatering(homeSphere.plants, asOf: now)
        }
        if on(.subscription) {
            plans += NotificationPlanBuilder.subscriptionRenewals(
                finance.subscriptions, symbol: currentCurrency.symbol, asOf: now
            )
        }
        if on(.morningBrief) {
            plans.append(NotificationPlanBuilder.daily(
                category: .morningBrief, id: "main",
                title: "Your morning brief is ready",
                body: "See what matters across your spheres today.",
                hour: 8
            ))
        }

        await NotificationEngine.sync(plans, categories: Set(NotificationCategory.allCases))
    }

    private var currentCurrency: Currency {
        UserDefaults.standard.string(forKey: Prefs.currency)
            .flatMap(Currency.init(rawValue:)) ?? .deviceDefault
    }

    /// Reflects the profile's sick/vacation state into the stores that honor
    /// it: Home suppresses daily nags and Mindfulness bridges its streak.
    func applyWellbeing(asOf now: Date = Date()) {
        home.isPaused = profile.profile.isWellbeingPaused(asOf: now)
        mindfulness.excusedStreakDays = profile.profile.wellbeingExcusedDays(asOf: now)
    }

    /// Sets or clears forgiveness (sick/vacation) mode, then re-applies it.
    func setWellbeing(_ mode: WellbeingMode, until: Date?) async {
        let now = Date()
        try? await profile.update { profile in
            profile.wellbeingMode = mode
            if mode == .normal {
                profile.wellbeingSince = nil
                profile.wellbeingUntil = nil
            } else {
                if profile.wellbeingSince == nil { profile.wellbeingSince = now }
                profile.wellbeingUntil = until
            }
        }
        applyWellbeing(asOf: now)
        refreshWidget()
    }

    /// Call after any store mutation (or a settings toggle) so scheduled
    /// reminders track the latest data.
    func refreshReminders() async {
        await syncReminders()
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

    /// Runs universal quick capture: the rule parser routes each fact in the
    /// text to its sphere tool, executes it, and returns confirmation chips.
    /// Refreshes the widget so a captured log shows on the home screen too.
    func quickCapture(_ text: String) async -> [CaptureResult] {
        let results = await QuickCapture.run(text, registry: toolRegistry)
        refreshWidget()
        return results
    }

    /// Agent-driven capture: when a tool-capable backend is available, the
    /// agent routes the note (and any photos) across every sphere; otherwise it
    /// falls back to the free rule-based parser for plain text. Refreshes the
    /// widget when anything was logged.
    func agentCapture(_ text: String, images: [Data]) async -> [CaptureResult] {
        if agent.isAvailable() {
            let llmImages = images.map {
                LLMImage(mimeType: "image/jpeg", base64Data: $0.base64EncodedString())
            }
            if let results = try? await agent.capture(
                text: text, images: llmImages, tools: toolRegistry
            ), !results.isEmpty {
                refreshWidget()
                return results
            }
        }
        // No agent (or it routed nothing): the free rule parser handles text.
        guard !text.isEmpty else { return [] }
        return await quickCapture(text)
    }

    /// Applies a quick-log command sent from the watch, then pushes a fresh
    /// snapshot back. Reloads the affected store first so a background wake
    /// mutates the real persisted state, not a zeroed in-memory default.
    func apply(_ command: WatchCommand) async {
        switch command {
        case .logWater:
            // load() first so the snapshot pushed back reflects full health
            // state; the increment itself is atomic in SQL (no lost updates).
            try? await health.load()
            try? await health.incrementWater()
        case .logMood(let score):
            try? await mindfulness.load()
            try? await mindfulness.setMood(score)
        case .logMeditation(let minutes):
            try? await mindfulness.load()
            try? await mindfulness.add(MeditationSession(
                id: MeditationSession.newID(),
                type: .breathing,
                durationMinutes: minutes,
                date: Date()
            ))
        case .checkShopping(let id):
            try? await homeSphere.load()
            try? await homeSphere.toggleShoppingItem(id: id)
        case .askAgent(let query):
            // Kept for backward compat with an old watch build; new builds
            // send .capture instead.
            lastAgentReply = (try? await agent.answer(query))
                ?? "Couldn't reach the assistant."
            lastCaptureResults = []
            lastAgentReplyAt = Date()
        case .capture(let text):
            switch await agent.captureOrAnswer(text: text, tools: toolRegistry) {
            case .captured(let results):
                lastCaptureResults = results
                lastAgentReply = nil
            case .answered(let text):
                lastAgentReply = text
                lastCaptureResults = []
            }
            // Stamped in both branches: the watch's Thinking… state ends as
            // soon as this is newer than the submission time, regardless of
            // which branch answered.
            lastAgentReplyAt = Date()
        }
        refreshWidget()
    }

    /// Last answer to a watch voice query, surfaced on the next snapshot.
    private var lastAgentReply: String?
    /// Confirmation chips from the last wrist capture, surfaced on the next
    /// snapshot. Mutually exclusive with `lastAgentReply`.
    private var lastCaptureResults: [CaptureResult] = []
    /// When `lastAgentReply`/`lastCaptureResults` was last updated; nil until
    /// the first watch submission resolves. The watch uses this to detect a
    /// fresh reply and to render a relative "Xm ago" timestamp under it.
    private var lastAgentReplyAt: Date?

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
            shopping: homeSphere.shopping.filter { !$0.checked }.prefix(6).map {
                WidgetSnapshot.ShoppingLine(id: $0.id, title: $0.name)
            },
            agentReply: lastAgentReply,
            agentReplyAt: lastAgentReplyAt,
            captureResults: lastCaptureResults.map {
                WidgetSnapshot.CaptureLine(summary: $0.summary, isError: $0.isError)
            },
            waterToday: health.waterToday,
            waterGoal: HealthStore.waterGoalGlasses,
            meditatedToday: mindfulness.hasMeditated(),
            moodToday: mindfulness.todaysMood(),
            updatedAt: Date()
        )
        store.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        WatchBridge.shared.send(snapshot)
    }
}

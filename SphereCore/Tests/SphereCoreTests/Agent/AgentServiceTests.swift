import Foundation
import Testing
@testable import SphereCore

@Suite("AgentService")
struct AgentServiceTests {
    private func makeService(
        engine: StubEngine,
        keys: [LLMProviderID: String] = [.anthropic: "key"],
        cache: (any OfflineCache)? = nil
    ) throws -> (service: AgentService, engram: EngramStore, cache: InMemoryCache) {
        let engram = try EngramStore.inMemory()
        let memoryCache = InMemoryCache()
        let service = AgentService(
            keyStore: InMemoryAPIKeyStore(keys),
            engram: engram,
            cache: cache ?? memoryCache,
            engineFactory: { _ in engine }
        )
        return (service, engram, memoryCache)
    }

    private func waterRegistry(silent: Bool = false) -> SphereToolRegistry {
        SphereToolRegistry(tools: [
            SphereTool(
                definition: LLMTool(name: "log_water_glass", description: "Log water", inputSchema: ["type": "object"]),
                spheres: [.health],
                silent: silent,
                confirmation: { _ in "Logged 1 glass of water" },
                handler: { _ in "{\"ok\":true}" }
            ),
        ])
    }

    private func collect(_ stream: AsyncThrowingStream<AgentChatEvent, Error>) async throws -> [AgentChatEvent] {
        var events: [AgentChatEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    @Test func chatRunsToolLoopAndRemembers() async throws {
        let engine = StubEngine(scripts: [
            [
                .toolCall(LLMToolCall(id: "tu_1", name: "log_water_glass", input: ["count": 1])),
                .stop(.toolUse),
            ],
            [.textDelta("Nice, "), .textDelta("logged!"), .stop(.endTurn)],
        ])
        let (service, engram, _) = try makeService(engine: engine)

        let events = try await collect(service.chat(
            sphere: "health",
            message: "I just drank a glass of water",
            userName: "Yuko",
            tools: waterRegistry(),
            sphereType: .health
        ))

        #expect(events == [
            .tool(confirmation: "Logged 1 glass of water", isError: false),
            .text("Nice, "),
            .text("logged!"),
            .end,
        ])

        // Two LLM turns; second turn carries the tool round-trip.
        #expect(engine.calls.count == 2)
        let second = engine.calls[1]
        #expect(second.messages.count == 3)
        #expect(second.messages[1].toolCalls.first?.name == "log_water_glass")
        #expect(second.messages[2].toolResults.first?.toolCallId == "tu_1")
        #expect(second.tools.map(\.name) == ["log_water_glass"])

        // System prompt: domain, name, tools hint.
        #expect(second.system.contains("Health & Fitness"))
        #expect(second.system.contains("Yuko"))
        #expect(second.system.contains("read-only lookup tool"))

        // Both sides of the conversation observed into Engram.
        #expect(try await engram.count(agentId: "health") == 2)
        let recalled = try await engram.recall("water", agentId: "health")
        #expect(recalled.contains { $0.content.hasPrefix("User: I just drank") })
    }

    @Test func memoryFromPastChatsEntersSystemPrompt() async throws {
        let engine = StubEngine(scripts: [[.textDelta("Hi"), .stop(.endTurn)]])
        let (service, engram, _) = try makeService(engine: engine)
        try await engram.observe(
            agentId: "health", content: "User ran 5 km on Tuesday", salience: 0.8
        )

        _ = try await collect(service.chat(sphere: "health", message: "How is my running?"))

        #expect(engine.calls[0].system.contains("<memory>"))
        #expect(engine.calls[0].system.contains("ran 5 km"))
    }

    @Test func silentToolYieldsNoChip() async throws {
        let engine = StubEngine(scripts: [
            [.toolCall(LLMToolCall(id: "t1", name: "log_water_glass", input: .object([:]))), .stop(.toolUse)],
            [.textDelta("Done"), .stop(.endTurn)],
        ])
        let (service, _, _) = try makeService(engine: engine)

        let events = try await collect(service.chat(
            sphere: "health", message: "check", tools: waterRegistry(silent: true), sphereType: .health
        ))
        #expect(events == [.text("Done"), .end])
    }

    @Test func unknownToolReportsFailureAndLoopContinues() async throws {
        let engine = StubEngine(scripts: [
            [.toolCall(LLMToolCall(id: "t1", name: "ghost_tool", input: .object([:]))), .stop(.toolUse)],
            [.textDelta("Sorry"), .stop(.endTurn)],
        ])
        let (service, _, _) = try makeService(engine: engine)

        let events = try await collect(service.chat(
            sphere: "health", message: "hm", tools: waterRegistry(), sphereType: .health
        ))
        #expect(events == [
            .tool(confirmation: "Tool ghost_tool failed", isError: true),
            .text("Sorry"),
            .end,
        ])
        // The error result still went back to the model.
        #expect(engine.calls[1].messages[2].toolResults.first?.isError == true)
    }

    @Test func maxTurnsBoundsRunawayToolLoops() async throws {
        let loopScript: [LLMEvent] = [
            .toolCall(LLMToolCall(id: "t", name: "log_water_glass", input: .object([:]))),
            .stop(.toolUse),
        ]
        let engine = StubEngine(scripts: Array(repeating: loopScript, count: 10))
        let (service, _, _) = try makeService(engine: engine)

        _ = try await collect(service.chat(
            sphere: "health", message: "go", tools: waterRegistry(), sphereType: .health, maxTurns: 3
        ))
        #expect(engine.calls.count == 3)
    }

    @Test func registryWithoutSphereTypeOffersNoTools() async throws {
        let engine = StubEngine(scripts: [[.textDelta("Hi"), .stop(.endTurn)]])
        let (service, _, _) = try makeService(engine: engine)

        _ = try await collect(service.chat(
            sphere: "health", message: "hello", tools: waterRegistry(), sphereType: nil
        ))
        #expect(engine.calls[0].tools.isEmpty)
        #expect(!engine.calls[0].system.contains("read-only lookup tool"))
    }

    @Test func noApiKeyThrows() async throws {
        let engine = StubEngine()
        let (service, _, _) = try makeService(engine: engine, keys: [:])

        await #expect(throws: AgentError.noApiKey) {
            _ = try await collect(service.chat(sphere: "health", message: "hi"))
        }
    }

    @Test func providerPriorityPrefersEarlierProvider() throws {
        let engine = StubEngine()
        let (service, _, _) = try makeService(
            engine: engine,
            keys: [.gemini: "g-key", .openrouter: "or-key"]
        )
        #expect(service.activeProviderName() == "Gemini")
        #expect(service.isAvailable())
    }

    @Test func apiErrorsSurfaceAsAgentErrors() async throws {
        let engine = StubEngine()
        engine.streamError = .api("rate limited")
        let (service, _, _) = try makeService(engine: engine)

        await #expect(throws: AgentError.api("rate limited")) {
            _ = try await collect(service.chat(sphere: "health", message: "hi"))
        }
    }

    @Test func briefStreamsCachesAndObserves() async throws {
        let engine = StubEngine(scripts: [[.textDelta("Morning, "), .textDelta("Yuko!"), .stop(.endTurn)]])
        let (service, engram, cache) = try makeService(engine: engine)

        var chunks: [String] = []
        for try await chunk in service.brief(calendarContext: "Standup at 10:00") {
            chunks.append(chunk)
        }
        #expect(chunks.joined() == "Morning, Yuko!")
        #expect(await cache.loadBrief() == "Morning, Yuko!")
        #expect(try await engram.count(agentId: "meta") == 1)
        #expect(engine.calls[0].system.contains("Calendar: Standup at 10:00"))
        #expect(engine.calls[0].system.contains("Meta Agent"))
    }

    @Test func briefFallsBackToCacheWhenOffline() async throws {
        let engine = StubEngine()
        engine.streamError = .backendUnavailable
        let (service, _, cache) = try makeService(engine: engine)
        await cache.saveBrief("Cached brief")

        var chunks: [String] = []
        for try await chunk in service.brief() {
            chunks.append(chunk)
        }
        #expect(chunks == ["Cached brief"])
    }

    @Test func briefWithoutCacheThrowsWhenOffline() async throws {
        let engine = StubEngine()
        engine.streamError = .backendUnavailable
        let (service, _, _) = try makeService(engine: engine)

        await #expect(throws: AgentError.backendUnavailable) {
            for try await _ in service.brief() {}
        }
    }

    @Test func insightParsesJsonOutOfProse() async throws {
        let engine = StubEngine()
        engine.completeResult =
            "Sure! {\"insight\":\"You sleep better after evening walks\",\"tags\":[\"health\",\"rest\"]} Hope this helps."
        let (service, _, cache) = try makeService(engine: engine)

        let insight = try await service.insight()
        #expect(insight == AgentInsight(
            insight: "You sleep better after evening walks",
            tags: ["health", "rest"]
        ))
        #expect(await cache.loadInsight() == insight)
    }

    @Test func insightFallsBackToRawTextWhenNotJson() async throws {
        let engine = StubEngine()
        engine.completeResult = "Walk more."
        let (service, _, _) = try makeService(engine: engine)

        let insight = try await service.insight()
        #expect(insight == AgentInsight(insight: "Walk more.", tags: ["Meta Agent"]))
    }

    @Test func insightFallsBackToCacheWhenOffline() async throws {
        let engine = StubEngine()
        engine.completeError = .backendUnavailable
        let cached = AgentInsight(insight: "Cached", tags: ["meta"])
        let (service, _, cache) = try makeService(engine: engine)
        await cache.saveInsight(cached)

        #expect(try await service.insight() == cached)
    }
}

/// In-memory OfflineCache for tests.
final class InMemoryCache: OfflineCache, @unchecked Sendable {
    private let lock = NSLock()
    private var brief: String?
    private var insight: AgentInsight?

    func loadBrief() async -> String? { lock.withLock { brief } }
    func saveBrief(_ text: String) async { lock.withLock { brief = text } }
    func loadInsight() async -> AgentInsight? { lock.withLock { insight } }
    func saveInsight(_ value: AgentInsight) async { lock.withLock { insight = value } }
}

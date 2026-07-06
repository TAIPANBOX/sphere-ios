import Foundation
import Testing
@testable import SphereCore

@Suite("AgentService.assist")
struct AgentAssistTests {
    private func makeService(
        engine: StubEngine, keys: [LLMProviderID: String] = [.openrouter: "key"]
    ) throws -> (AgentService, EngramStore) {
        let engram = try EngramStore.inMemory()
        let service = AgentService(
            keyStore: InMemoryAPIKeyStore(keys),
            engram: engram,
            cache: InMemoryCache(),
            engineFactory: { _ in engine }
        )
        return (service, engram)
    }

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var text = ""
        for try await chunk in stream { text += chunk }
        return text
    }

    @Test func decomposeGoalStreamsAndObserves() async throws {
        let engine = StubEngine(scripts: [[.textDelta("1. "), .textDelta("Milestone"), .stop(.endTurn)]])
        let (service, engram) = try makeService(engine: engine)

        let text = try await collect(service.assist(.decomposeGoal(title: "Run a 10k", why: "health")))
        #expect(text == "1. Milestone")

        // Goal plans are filed back into Engram.
        let recalled = try await engram.crossAgentRecall("Milestone")
        #expect(recalled.contains { $0.content.contains("Goal plan") })
    }

    @Test func prepBriefingRecallsThenStreams() async throws {
        let engine = StubEngine(scripts: [[.textDelta("Ask about her trip."), .stop(.endTurn)]])
        let (service, engram) = try makeService(engine: engine)
        try await engram.observe(
            agentId: "relationships", content: "Maria just moved to Lisbon",
            tags: ["contact"], salience: 0.7
        )

        let text = try await collect(
            service.assist(.prepBriefing(contact: "Maria", facts: ["Last talked 3 weeks ago"]))
        )
        #expect(text.contains("trip"))
    }

    @Test func interviewQuestionsDoNotObserve() async throws {
        let engine = StubEngine(scripts: [[.textDelta("Q1?"), .stop(.endTurn)]])
        let (service, engram) = try makeService(engine: engine)

        _ = try await collect(
            service.assist(.interviewQuestions(role: "iOS Eng", jobDescription: "Swift, GRDB"))
        )
        let recalled = try await engram.crossAgentRecall("Q1")
        #expect(recalled.isEmpty)
    }

    @Test func assistSurfacesBackendError() async throws {
        let engine = StubEngine()
        engine.streamError = .backendUnavailable
        let (service, _) = try makeService(engine: engine)

        await #expect(throws: (any Error).self) {
            _ = try await collect(service.assist(.analyzePatterns(scope: "my life", facts: ["Mood up"])))
        }
    }
}

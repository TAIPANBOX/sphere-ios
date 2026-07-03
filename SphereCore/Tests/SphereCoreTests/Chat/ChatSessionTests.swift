import Foundation
import Testing
@testable import SphereCore

@Suite("ChatSession")
@MainActor
struct ChatSessionTests {
    private func makeSession(
        engine: StubEngine,
        sphereName: String = "Goals",
        sphereType: SphereType? = .goals,
        tools: SphereToolRegistry? = nil,
        keys: [LLMProviderID: String] = [.anthropic: "key"]
    ) throws -> ChatSession {
        let agent = AgentService(
            keyStore: InMemoryAPIKeyStore(keys),
            engram: try EngramStore.inMemory(),
            cache: InMemoryCache(),
            engineFactory: { _ in engine }
        )
        return ChatSession(
            sphereName: sphereName, sphereType: sphereType, agent: agent,
            tools: tools, userName: "Yuko"
        )
    }

    @Test func greetingIsSphereSpecific() throws {
        let plain = try makeSession(engine: StubEngine())
        #expect(plain.messages.first?.content == "Hey! I'm your Goals agent. What's on your mind?")

        let health = try makeSession(engine: StubEngine(), sphereName: "Health", sphereType: .health)
        #expect(health.messages.first?.content.contains("🫀") == true)
    }

    @Test func sendStreamsIntoOneAgentBubble() async throws {
        let engine = StubEngine(scripts: [[
            .textDelta("Прив"), .textDelta("іт!"), .stop(.endTurn),
        ]])
        let session = try makeSession(engine: engine)

        await session.send("Як мої цілі?")

        #expect(session.messages.count == 3)
        #expect(session.messages[1].isUser)
        #expect(session.messages[1].content == "Як мої цілі?")
        let reply = session.messages[2]
        #expect(reply.content == "Привіт!")
        #expect(!reply.isTyping)
        #expect(!reply.isStreaming)
        #expect(!session.isBusy)
    }

    @Test func literalBackslashNIsDecoded() async throws {
        let engine = StubEngine(scripts: [[.textDelta("line1\\nline2"), .stop(.endTurn)]])
        let session = try makeSession(engine: engine)
        await session.send("hi")
        #expect(session.messages.last?.content == "line1\nline2")
    }

    @Test func toolFlowInsertsChipAndFreshBubble() async throws {
        let tools = SphereToolRegistry(tools: [
            SphereTool(
                definition: LLMTool(name: "add_goal", description: "d", inputSchema: ["type": "object"]),
                spheres: [.goals],
                confirmation: { _ in "Added goal: Japan" },
                handler: { _ in "{\"ok\":true}" }
            ),
        ])
        let engine = StubEngine(scripts: [
            [
                .toolCall(LLMToolCall(id: "c1", name: "add_goal", input: ["title": "Japan"])),
                .stop(.toolUse),
            ],
            [.textDelta("Done — added it!"), .stop(.endTurn)],
        ])
        let session = try makeSession(engine: engine, tools: tools)

        await session.send("Add a goal to visit Japan")

        // greeting, user, tool chip, agent reply (empty first bubble dropped)
        #expect(session.messages.count == 4)
        let chip = session.messages[2]
        #expect(chip.isToolConfirmation)
        #expect(chip.content == "Added goal: Japan")
        #expect(!chip.isError)
        #expect(session.messages[3].content == "Done — added it!")
    }

    @Test func trailingEmptyBubbleIsDroppedWhenToolEndsTurn() async throws {
        let tools = SphereToolRegistry(tools: [
            SphereTool(
                definition: LLMTool(name: "log", description: "d", inputSchema: ["type": "object"]),
                spheres: [.goals],
                confirmation: { _ in "Logged" },
                handler: { _ in "{}" }
            ),
        ])
        // The model calls a tool and the second turn produces no text at all.
        let engine = StubEngine(scripts: [
            [.toolCall(LLMToolCall(id: "c1", name: "log", input: .object([:]))), .stop(.toolUse)],
            [.stop(.endTurn)],
        ])
        let session = try makeSession(engine: engine, tools: tools)

        await session.send("log it")

        #expect(session.messages.count == 3)
        #expect(session.messages.last?.isToolConfirmation == true)
        #expect(!session.messages.contains { $0.isTyping })
    }

    @Test func historyExcludesGreetingChipsAndPlaceholdersImages() async throws {
        let engine = StubEngine(scripts: [
            [.textDelta("First reply"), .stop(.endTurn)],
            [.textDelta("Second reply"), .stop(.endTurn)],
        ])
        let session = try makeSession(engine: engine)

        await session.send("", images: [LLMImage(mimeType: "image/jpeg", base64Data: "AAA=")])
        await session.send("And a follow-up")

        // The second engine call receives history: image placeholder + reply.
        let second = engine.calls[1]
        #expect(second.messages.count == 3)
        #expect(second.messages[0].text == "[shared 1 image]")
        #expect(second.messages[0].role == .user)
        #expect(second.messages[1].text == "First reply")
        #expect(second.messages[1].role == .assistant)
        #expect(second.messages[2].text == "And a follow-up")
    }

    @Test func noApiKeyShowsSettingsHint() async throws {
        let session = try makeSession(engine: StubEngine(), keys: [:])
        await session.send("hello")

        let last = try #require(session.messages.last)
        #expect(last.content.contains("Settings → AI Agents"))
        #expect(last.isError)
        #expect(!last.isTyping)
    }

    @Test func apiErrorSurfacesMessage() async throws {
        let engine = StubEngine()
        engine.streamError = .api("quota exceeded")
        let session = try makeSession(engine: engine)
        await session.send("hello")

        #expect(session.messages.last?.content == "AI error: quota exceeded")
        #expect(session.messages.last?.isError == true)
    }

    @Test func resetRestoresGreetingOnly() async throws {
        let engine = StubEngine(scripts: [[.textDelta("Hi"), .stop(.endTurn)]])
        let session = try makeSession(engine: engine)
        await session.send("hello")
        #expect(session.messages.count == 3)

        session.reset()
        #expect(session.messages.count == 1)
        #expect(session.messages[0].content.contains("Goals agent"))
    }
}

import Foundation
import Testing
@testable import SphereCore

@Suite("OpenAICompatibleEngine")
struct OpenAICompatibleEngineTests {
    private func engine(_ transport: StubTransport) -> OpenAICompatibleEngine {
        OpenAICompatibleEngine(
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            model: "anthropic/claude-haiku-4.5",
            extraHeaders: ["HTTP-Referer": "https://sphere.app", "X-Title": "Sphere"],
            transport: transport
        )
    }

    @Test func streamsTextThenFlushesToolCallsOnDone() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"Хвилинку"}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"log_water","arguments":"{\\"amo"}}]}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"unt\\": 300}"}}]}}]}

        data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

        data: [DONE]

        """
        let transport = StubTransport(body: sse, chunkSize: 5)
        let events = try await collectEvents(
            engine(transport).stream(apiKey: "key", system: "sys", messages: [.user("hi")])
        )

        #expect(events == [
            .textDelta("Хвилинку"),
            .toolCall(LLMToolCall(id: "call_1", name: "log_water", input: ["amount": 300])),
            .stop(.toolUse),
        ])
    }

    @Test func plainCompletionStopsWithEndTurn() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"Hi!"},"finish_reason":null}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        """
        let transport = StubTransport(body: sse)
        let events = try await collectEvents(
            engine(transport).stream(apiKey: "k", system: "s", messages: [.user("q")])
        )
        #expect(events == [.textDelta("Hi!"), .stop(.endTurn)])
    }

    @Test func parallelToolCallsFlushInIndexOrder() async throws {
        let sse = """
        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c0","function":{"name":"get_health_today","arguments":"{}"}},{"index":1,"id":"c1","function":{"name":"list_goals","arguments":"{}"}}]}}]}

        data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

        data: [DONE]

        """
        let transport = StubTransport(body: sse)
        let events = try await collectEvents(
            engine(transport).stream(apiKey: "k", system: "s", messages: [.user("q")])
        )
        #expect(events == [
            .toolCall(LLMToolCall(id: "c0", name: "get_health_today", input: .object([:]))),
            .toolCall(LLMToolCall(id: "c1", name: "list_goals", input: .object([:]))),
            .stop(.toolUse),
        ])
    }

    @Test func apiErrorSurfacesMessage() async throws {
        let transport = StubTransport(
            status: 402,
            body: "{\"error\":{\"message\":\"Insufficient credits\",\"code\":402}}"
        )
        await #expect(throws: LLMError.api("Insufficient credits")) {
            _ = try await collectEvents(
                engine(transport).stream(apiKey: "k", system: "s", messages: [.user("q")])
            )
        }
    }

    @Test func requestBodyAndHeadersMatchAPI() async throws {
        let transport = StubTransport(body: "data: [DONE]\n")
        let tool = LLMTool(
            name: "log_water",
            description: "Log water intake",
            inputSchema: ["type": "object"]
        )
        let messages: [LLMMessage] = [
            .user("How much water today?"),
            .assistant("", toolCalls: [LLMToolCall(id: "c1", name: "log_water", input: ["amount": 300])]),
            .toolResults([LLMToolResult(toolCallId: "c1", content: "logged")]),
        ]
        _ = try await collectEvents(
            engine(transport).stream(
                apiKey: "secret", system: "You are Health.", messages: messages,
                tools: [tool], maxTokens: 512
            )
        )

        let request = try #require(transport.requests.last)
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "HTTP-Referer") == "https://sphere.app")
        #expect(request.value(forHTTPHeaderField: "X-Title") == "Sphere")

        let body = try #require(transport.lastRequestBody)
        #expect(body["tools"]?[0]?["type"]?.stringValue == "function")
        #expect(body["tools"]?[0]?["function"]?["name"]?.stringValue == "log_water")

        let serialized = try #require(body["messages"]?.arrayValue)
        #expect(serialized.count == 4)
        #expect(serialized[0]["role"]?.stringValue == "system")
        #expect(serialized[0]["content"]?.stringValue == "You are Health.")
        #expect(serialized[1]["content"]?.stringValue == "How much water today?")
        #expect(serialized[2]["tool_calls"]?[0]?["function"]?["name"]?.stringValue == "log_water")
        #expect(serialized[3]["role"]?.stringValue == "tool")
        #expect(serialized[3]["tool_call_id"]?.stringValue == "c1")
    }

    @Test func imagesSerializeAsDataUrls() async throws {
        let transport = StubTransport(body: "data: [DONE]\n")
        let message = LLMMessage.user(
            "What is this?",
            images: [LLMImage(mimeType: "image/jpeg", base64Data: "AAA=")]
        )
        _ = try await collectEvents(
            engine(transport).stream(apiKey: "k", system: "s", messages: [message])
        )

        let content = try #require(
            transport.lastRequestBody?["messages"]?[1]?["content"]?.arrayValue
        )
        #expect(content[0]["type"]?.stringValue == "text")
        #expect(content[1]["image_url"]?["url"]?.stringValue == "data:image/jpeg;base64,AAA=")
    }

    @Test func completeReturnsMessageContent() async throws {
        let transport = StubTransport(
            body: "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Brief.\"}}]}"
        )
        let text = try await engine(transport).complete(apiKey: "k", system: "s", prompt: "go")
        #expect(text == "Brief.")
    }

    @Test func providerRegistryWiresEnginesAndModels() throws {
        #expect(LLMProviderID.anthropic.makeEngine() is AnthropicEngine)
        #expect(LLMProviderID.openai.makeEngine() is OpenAICompatibleEngine)
        #expect(LLMProviderID.gemini.makeEngine() is OpenAICompatibleEngine)

        let openrouter = try #require(LLMProviderID.openrouter.makeEngine() as? OpenAICompatibleEngine)
        #expect(openrouter.baseURL.absoluteString == "https://openrouter.ai/api/v1")
        #expect(openrouter.extraHeaders["X-Title"] == "Sphere")

        let gemini = try #require(LLMProviderID.gemini.makeEngine(model: "gemini-2.5-pro") as? OpenAICompatibleEngine)
        #expect(gemini.model == "gemini-2.5-pro")
        #expect(gemini.baseURL.absoluteString.contains("generativelanguage.googleapis.com"))
    }
}

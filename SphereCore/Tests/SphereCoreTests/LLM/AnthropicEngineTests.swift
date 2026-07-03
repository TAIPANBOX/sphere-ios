import Foundation
import Testing
@testable import SphereCore

@Suite("AnthropicEngine")
struct AnthropicEngineTests {
    private func engine(_ transport: StubTransport) -> AnthropicEngine {
        AnthropicEngine(model: "claude-haiku-4-5", transport: transport)
    }

    @Test func streamsTextToolCallAndStop() async throws {
        let sse = """
        event: message_start
        data: {"type":"message_start"}

        data: {"type":"content_block_start","index":0,"content_block":{"type":"text"}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Прив"}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"іт!"}}

        data: {"type":"content_block_stop","index":0}

        data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tu_1","name":"log_water"}}

        data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"amount\\""}}

        data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":": 300}"}}

        data: {"type":"content_block_stop","index":1}

        data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}

        data: {"type":"message_stop"}

        """
        let transport = StubTransport(body: sse, chunkSize: 7)
        let events = try await collectEvents(
            engine(transport).stream(
                apiKey: "key", system: "sys", messages: [.user("hi")], tools: [], maxTokens: 256
            )
        )

        #expect(events == [
            .textDelta("Прив"),
            .textDelta("іт!"),
            .toolCall(LLMToolCall(id: "tu_1", name: "log_water", input: ["amount": 300])),
            .stop(.toolUse),
        ])
    }

    @Test func endTurnWithoutTools() async throws {
        let sse = """
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Done"}}

        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}

        data: {"type":"message_stop"}

        """
        let transport = StubTransport(body: sse)
        let events = try await collectEvents(
            engine(transport).stream(apiKey: "k", system: "s", messages: [.user("q")])
        )
        #expect(events == [.textDelta("Done"), .stop(.endTurn)])
    }

    @Test func malformedToolJsonFallsBackToEmptyInput() async throws {
        let sse = """
        data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"tu_2","name":"list_goals"}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{broken"}}

        data: {"type":"content_block_stop","index":0}

        data: {"type":"message_stop"}

        """
        let transport = StubTransport(body: sse)
        let events = try await collectEvents(
            engine(transport).stream(apiKey: "k", system: "s", messages: [.user("q")])
        )
        #expect(events.first == .toolCall(LLMToolCall(id: "tu_2", name: "list_goals", input: .object([:]))))
    }

    @Test func apiErrorSurfacesMessage() async throws {
        let transport = StubTransport(
            status: 401,
            body: "{\"type\":\"error\",\"error\":{\"type\":\"authentication_error\",\"message\":\"invalid x-api-key\"}}"
        )
        await #expect(throws: LLMError.api("invalid x-api-key")) {
            _ = try await collectEvents(
                engine(transport).stream(apiKey: "bad", system: "s", messages: [.user("q")])
            )
        }
    }

    @Test func requestBodyAndHeadersMatchAPI() async throws {
        let transport = StubTransport(body: "data: {\"type\":\"message_stop\"}\n")
        let tool = LLMTool(
            name: "log_water",
            description: "Log water intake",
            inputSchema: ["type": "object", "properties": ["amount": ["type": "number"]]]
        )
        let messages: [LLMMessage] = [
            .user("How much water today?"),
            .assistant("", toolCalls: [LLMToolCall(id: "tu_1", name: "log_water", input: ["amount": 300])]),
            .toolResults([LLMToolResult(toolCallId: "tu_1", content: "logged", isError: false)]),
        ]
        _ = try await collectEvents(
            engine(transport).stream(
                apiKey: "secret", system: "You are Health.", messages: messages,
                tools: [tool], maxTokens: 777
            )
        )

        let request = try #require(transport.requests.last)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "secret")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")

        let body = try #require(transport.lastRequestBody)
        #expect(body["model"]?.stringValue == "claude-haiku-4-5")
        #expect(body["max_tokens"]?.intValue == 777)
        #expect(body["stream"]?.boolValue == true)
        #expect(body["system"]?.stringValue == "You are Health.")
        #expect(body["tools"]?[0]?["input_schema"]?["type"]?.stringValue == "object")

        let serialized = try #require(body["messages"]?.arrayValue)
        #expect(serialized.count == 3)
        #expect(serialized[0]["content"]?.stringValue == "How much water today?")
        #expect(serialized[1]["content"]?[0]?["type"]?.stringValue == "tool_use")
        #expect(serialized[2]["role"]?.stringValue == "user")
        #expect(serialized[2]["content"]?[0]?["type"]?.stringValue == "tool_result")
        #expect(serialized[2]["content"]?[0]?["tool_use_id"]?.stringValue == "tu_1")
    }

    @Test func imagesSerializeAsBase64Blocks() async throws {
        let transport = StubTransport(body: "data: {\"type\":\"message_stop\"}\n")
        let message = LLMMessage.user(
            "What is this?",
            images: [LLMImage(mimeType: "image/png", base64Data: "AAA=")]
        )
        _ = try await collectEvents(
            engine(transport).stream(apiKey: "k", system: "s", messages: [message])
        )

        let content = try #require(transport.lastRequestBody?["messages"]?[0]?["content"]?.arrayValue)
        #expect(content[0]["type"]?.stringValue == "image")
        #expect(content[0]["source"]?["media_type"]?.stringValue == "image/png")
        #expect(content[1]["type"]?.stringValue == "text")
    }

    @Test func completeReturnsFirstTextBlock() async throws {
        let transport = StubTransport(
            body: "{\"content\":[{\"type\":\"text\",\"text\":\"Morning brief.\"}]}"
        )
        let text = try await engine(transport).complete(
            apiKey: "k", system: "s", prompt: "brief"
        )
        #expect(text == "Morning brief.")
        #expect(transport.lastRequestBody?["stream"] == nil)
    }
}

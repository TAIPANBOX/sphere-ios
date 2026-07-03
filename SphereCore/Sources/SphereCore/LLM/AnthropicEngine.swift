import Foundation

/// Native Anthropic Messages API engine (SSE streaming + tool use).
public struct AnthropicEngine: LLMEngine {
    static let version = "2023-06-01"

    public let baseURL: URL
    public let model: String
    private let transport: any LLMTransport

    public init(
        model: String,
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        transport: any LLMTransport = URLSessionTransport()
    ) {
        self.model = model
        self.baseURL = baseURL
        self.transport = transport
    }

    public func stream(
        apiKey: String,
        system: String,
        messages: [LLMMessage],
        tools: [LLMTool],
        maxTokens: Int
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var body: [String: JSONValue] = [
                        "model": .string(model),
                        "max_tokens": .number(Double(maxTokens)),
                        "stream": .bool(true),
                        "system": .string(system),
                        "messages": .array(messages.map(Self.serialize)),
                    ]
                    if !tools.isEmpty {
                        body["tools"] = .array(tools.map { tool in
                            .object([
                                "name": .string(tool.name),
                                "description": .string(tool.description),
                                "input_schema": tool.inputSchema,
                            ])
                        })
                    }
                    let request = try LLMHTTP.makeRequest(
                        url: baseURL.appendingPathComponent("v1/messages"),
                        headers: headers(apiKey: apiKey),
                        body: .object(body)
                    )

                    let (status, bytes) = try await transport.stream(request)
                    guard (200..<300).contains(status) else {
                        throw LLMError.api(await LLMHTTP.errorMessage(status: status, bytes: bytes))
                    }

                    // Anthropic streams content blocks (text or tool_use). Tool
                    // arguments arrive as input_json_delta chunks accumulated per
                    // block index and emitted as one .toolCall on content_block_stop.
                    var stopReason: String?
                    var pendingTools: [Int: PendingTool] = [:]

                    for try await payload in SSE.dataLines(from: bytes) {
                        guard let json = JSONValue.decoded(from: payload) else { continue }
                        switch json["type"]?.stringValue {
                        case "content_block_start":
                            guard let index = json["index"]?.intValue,
                                  let block = json["content_block"],
                                  block["type"]?.stringValue == "tool_use",
                                  let id = block["id"]?.stringValue,
                                  let name = block["name"]?.stringValue
                            else { break }
                            pendingTools[index] = PendingTool(id: id, name: name)

                        case "content_block_delta":
                            guard let index = json["index"]?.intValue,
                                  let delta = json["delta"]
                            else { break }
                            switch delta["type"]?.stringValue {
                            case "text_delta":
                                if let text = delta["text"]?.stringValue, !text.isEmpty {
                                    continuation.yield(.textDelta(text))
                                }
                            case "input_json_delta":
                                pendingTools[index]?.json += delta["partial_json"]?.stringValue ?? ""
                            default:
                                break
                            }

                        case "content_block_stop":
                            guard let index = json["index"]?.intValue,
                                  let pending = pendingTools.removeValue(forKey: index)
                            else { break }
                            continuation.yield(.toolCall(pending.toolCall))

                        case "message_delta":
                            stopReason = json["delta"]?["stop_reason"]?.stringValue ?? stopReason

                        case "message_stop":
                            continuation.yield(.stop(StopReason(anthropic: stopReason)))
                            continuation.finish()
                            return

                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func complete(
        apiKey: String,
        system: String,
        prompt: String,
        maxTokens: Int
    ) async throws -> String {
        let body: JSONValue = .object([
            "model": .string(model),
            "max_tokens": .number(Double(maxTokens)),
            "system": .string(system),
            "messages": .array([.object(["role": "user", "content": .string(prompt)])]),
        ])
        let request = try LLMHTTP.makeRequest(
            url: baseURL.appendingPathComponent("v1/messages"),
            headers: headers(apiKey: apiKey),
            body: body
        )
        let (status, data) = try await transport.post(request)
        guard (200..<300).contains(status) else {
            throw LLMError.api(LLMHTTP.errorMessage(status: status, body: data))
        }
        let json = JSONValue.decoded(from: data)
        return json?["content"]?[0]?["text"]?.stringValue ?? ""
    }

    private func headers(apiKey: String) -> [String: String] {
        [
            "x-api-key": apiKey,
            "anthropic-version": Self.version,
        ]
    }

    static func serialize(_ message: LLMMessage) -> JSONValue {
        if !message.toolResults.isEmpty {
            return .object([
                "role": "user",
                "content": .array(message.toolResults.map { result in
                    var part: [String: JSONValue] = [
                        "type": "tool_result",
                        "tool_use_id": .string(result.toolCallId),
                        "content": .string(result.content),
                    ]
                    if result.isError { part["is_error"] = .bool(true) }
                    return .object(part)
                }),
            ])
        }

        if !message.toolCalls.isEmpty {
            var parts: [JSONValue] = []
            if !message.text.isEmpty {
                parts.append(.object(["type": "text", "text": .string(message.text)]))
            }
            for call in message.toolCalls {
                parts.append(.object([
                    "type": "tool_use",
                    "id": .string(call.id),
                    "name": .string(call.name),
                    "input": call.input,
                ]))
            }
            return .object(["role": .string(message.role.rawValue), "content": .array(parts)])
        }

        if message.images.isEmpty {
            return .object(["role": .string(message.role.rawValue), "content": .string(message.text)])
        }
        var parts: [JSONValue] = message.images.map { image in
            .object([
                "type": "image",
                "source": .object([
                    "type": "base64",
                    "media_type": .string(image.mimeType),
                    "data": .string(image.base64Data),
                ]),
            ])
        }
        if !message.text.isEmpty {
            parts.append(.object(["type": "text", "text": .string(message.text)]))
        }
        return .object(["role": .string(message.role.rawValue), "content": .array(parts)])
    }
}

private struct PendingTool {
    let id: String
    let name: String
    var json = ""

    var toolCall: LLMToolCall {
        LLMToolCall(
            id: id,
            name: name,
            input: json.isEmpty ? .object([:]) : (JSONValue.decoded(from: json) ?? .object([:]))
        )
    }
}

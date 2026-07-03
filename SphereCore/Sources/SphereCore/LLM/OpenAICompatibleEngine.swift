import Foundation

/// Chat Completions engine for every OpenAI-compatible API: OpenAI itself,
/// Gemini (via its OpenAI-compatible endpoint), and OpenRouter.
public struct OpenAICompatibleEngine: LLMEngine {
    public let baseURL: URL
    public let model: String
    public let extraHeaders: [String: String]
    private let transport: any LLMTransport

    public init(
        baseURL: URL,
        model: String,
        extraHeaders: [String: String] = [:],
        transport: any LLMTransport = URLSessionTransport()
    ) {
        self.baseURL = baseURL
        self.model = model
        self.extraHeaders = extraHeaders
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
                        "messages": .array(
                            [.object(["role": "system", "content": .string(system)])]
                                + messages.flatMap(Self.serialize)
                        ),
                    ]
                    if !tools.isEmpty {
                        body["tools"] = .array(tools.map { tool in
                            .object([
                                "type": "function",
                                "function": .object([
                                    "name": .string(tool.name),
                                    "description": .string(tool.description),
                                    "parameters": tool.inputSchema,
                                ]),
                            ])
                        })
                    }
                    let request = try LLMHTTP.makeRequest(
                        url: baseURL.appendingPathComponent("chat/completions"),
                        headers: headers(apiKey: apiKey),
                        body: .object(body)
                    )

                    let (status, bytes) = try await transport.stream(request)
                    guard (200..<300).contains(status) else {
                        throw LLMError.api(await LLMHTTP.errorMessage(status: status, bytes: bytes))
                    }

                    // Tool-call arguments stream as string fragments per call
                    // index; they are accumulated and flushed as .toolCall
                    // events when the stream signals [DONE].
                    var pendingTools: [Int: PendingTool] = [:]
                    var finishReason: String?

                    for try await payload in SSE.dataLines(from: bytes) {
                        if payload == "[DONE]" {
                            for index in pendingTools.keys.sorted() {
                                if let pending = pendingTools[index] {
                                    continuation.yield(.toolCall(pending.toolCall))
                                }
                            }
                            pendingTools.removeAll()
                            continuation.yield(.stop(StopReason(openAIFinishReason: finishReason)))
                            continuation.finish()
                            return
                        }
                        guard let json = JSONValue.decoded(from: payload),
                              let choice = json["choices"]?[0]
                        else { continue }

                        if let reason = choice["finish_reason"]?.stringValue {
                            finishReason = reason
                        }
                        guard let delta = choice["delta"] else { continue }

                        if let text = delta["content"]?.stringValue, !text.isEmpty {
                            continuation.yield(.textDelta(text))
                        }
                        for rawCall in delta["tool_calls"]?.arrayValue ?? [] {
                            let index = rawCall["index"]?.intValue ?? 0
                            var pending = pendingTools[index] ?? PendingTool()
                            if let id = rawCall["id"]?.stringValue, !id.isEmpty {
                                pending.id = id
                            }
                            if let name = rawCall["function"]?["name"]?.stringValue, !name.isEmpty {
                                pending.name = name
                            }
                            pending.json += rawCall["function"]?["arguments"]?.stringValue ?? ""
                            pendingTools[index] = pending
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
            "messages": .array([
                .object(["role": "system", "content": .string(system)]),
                .object(["role": "user", "content": .string(prompt)]),
            ]),
        ])
        let request = try LLMHTTP.makeRequest(
            url: baseURL.appendingPathComponent("chat/completions"),
            headers: headers(apiKey: apiKey),
            body: body
        )
        let (status, data) = try await transport.post(request)
        guard (200..<300).contains(status) else {
            throw LLMError.api(LLMHTTP.errorMessage(status: status, body: data))
        }
        let json = JSONValue.decoded(from: data)
        return json?["choices"]?[0]?["message"]?["content"]?.stringValue ?? ""
    }

    private func headers(apiKey: String) -> [String: String] {
        var headers = extraHeaders
        headers["Authorization"] = "Bearer \(apiKey)"
        return headers
    }

    static func serialize(_ message: LLMMessage) -> [JSONValue] {
        if !message.toolResults.isEmpty {
            return message.toolResults.map { result in
                .object([
                    "role": "tool",
                    "tool_call_id": .string(result.toolCallId),
                    "content": .string(result.content),
                ])
            }
        }

        if !message.toolCalls.isEmpty {
            return [.object([
                "role": .string(message.role.rawValue),
                "content": message.text.isEmpty ? .null : .string(message.text),
                "tool_calls": .array(message.toolCalls.map { call in
                    .object([
                        "id": .string(call.id),
                        "type": "function",
                        "function": .object([
                            "name": .string(call.name),
                            "arguments": .string(call.input.encodedString()),
                        ]),
                    ])
                }),
            ])]
        }

        if message.images.isEmpty {
            return [.object([
                "role": .string(message.role.rawValue),
                "content": .string(message.text),
            ])]
        }
        var parts: [JSONValue] = []
        if !message.text.isEmpty {
            parts.append(.object(["type": "text", "text": .string(message.text)]))
        }
        for image in message.images {
            parts.append(.object([
                "type": "image_url",
                "image_url": .object([
                    "url": .string("data:\(image.mimeType);base64,\(image.base64Data)"),
                ]),
            ]))
        }
        return [.object([
            "role": .string(message.role.rawValue),
            "content": .array(parts),
        ])]
    }
}

private struct PendingTool {
    var id = ""
    var name = ""
    var json = ""

    var toolCall: LLMToolCall {
        LLMToolCall(
            id: id,
            name: name,
            input: json.isEmpty ? .object([:]) : (JSONValue.decoded(from: json) ?? .object([:]))
        )
    }
}

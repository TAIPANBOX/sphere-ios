import Foundation

public enum AgentChatEvent: Sendable, Equatable {
    case text(String)
    case tool(confirmation: String, isError: Bool)
    case end
}

public enum AgentError: Error, Equatable, Sendable {
    /// No provider key configured. UI points to Settings → AI Agents.
    case noApiKey
    /// Offline or unreachable — retryable, cached surfaces may be shown.
    case backendUnavailable
    /// Provider rejected the request (bad key, quota, invalid input).
    case api(String)
}

/// Orchestrates one agent exchange: recall memories → build system prompt →
/// stream from the picked provider → dispatch tool calls → observe the
/// conversation back into Engram.
public final class AgentService: Sendable {
    private let keyStore: any APIKeyStore
    private let engram: EngramStore
    private let cache: any OfflineCache
    private let engineFactory: @Sendable (LLMProviderID) -> any LLMEngine
    /// Returns a ready on-device engine (Apple Foundation Models) when the
    /// system model is available, else nil. Injected by the app target so
    /// SphereCore stays free of the FoundationModels framework.
    private let onDeviceEngine: @Sendable () -> (any LLMEngine)?
    /// Returns an engine for the active downloaded model (AI Tier 1) when one
    /// is installed and selected, else nil. Injected by the app target so
    /// SphereCore stays free of the MLX frameworks.
    private let localModelEngine: @Sendable () -> (any LLMEngine)?
    /// The user's explicit backend choice, if any (else auto-resolve).
    private let preferredBackend: @Sendable () -> AIBackend?

    public init(
        keyStore: any APIKeyStore,
        engram: EngramStore,
        cache: any OfflineCache,
        engineFactory: @escaping @Sendable (LLMProviderID) -> any LLMEngine = { $0.makeEngine() },
        onDeviceEngine: @escaping @Sendable () -> (any LLMEngine)? = { nil },
        localModelEngine: @escaping @Sendable () -> (any LLMEngine)? = { nil },
        preferredBackend: @escaping @Sendable () -> AIBackend? = { nil }
    ) {
        self.keyStore = keyStore
        self.engram = engram
        self.cache = cache
        self.engineFactory = engineFactory
        self.onDeviceEngine = onDeviceEngine
        self.localModelEngine = localModelEngine
        self.preferredBackend = preferredBackend
    }

    // MARK: - Backend selection

    /// Resolves which backend answers this exchange. Order:
    /// 1. the user's explicit choice, if usable;
    /// 2. free on-device (Apple) when available;
    /// 3. the active downloaded model (Tier 1), when installed;
    /// 4. the OpenRouter key, when configured.
    /// Throws `noApiKey` only when none of the above is available.
    private func resolveBackend() throws -> (engine: any LLMEngine, apiKey: String, label: String) {
        if let preferred = preferredBackend() {
            switch preferred {
            case .onDevice:
                if let engine = onDeviceEngine() { return (engine, "", preferred.label) }
            case .localModel:
                if let engine = localModelEngine() { return (engine, "", preferred.label) }
            case .cloud(let provider):
                if let key = keyStore.key(for: provider), !key.isEmpty {
                    return (engineFactory(provider), key, provider.displayName)
                }
            }
        }
        if let engine = onDeviceEngine() { return (engine, "", AIBackend.onDevice.label) }
        if let engine = localModelEngine() { return (engine, "", AIBackend.localModel.label) }
        for provider in LLMProviderID.allCases {
            if let key = keyStore.key(for: provider), !key.isEmpty {
                return (engineFactory(provider), key, provider.displayName)
            }
        }
        throw AgentError.noApiKey
    }

    public func isAvailable() -> Bool {
        (try? resolveBackend()) != nil
    }

    public func activeProviderName() -> String? {
        (try? resolveBackend())?.label
    }

    // MARK: - Chat

    /// Streams chat events: text deltas, tool confirmations, and an end
    /// marker. When `tools` is provided, the model may invoke sphere-side
    /// actions; the loop feeds results back for up to `maxTurns` rounds.
    public func chat(
        sphere: String,
        message: String,
        userName: String = "",
        userContext: String = "",
        history: [LLMMessage] = [],
        images: [LLMImage] = [],
        tools: SphereToolRegistry? = nil,
        sphereType: SphereType? = nil,
        maxTurns: Int = 5
    ) -> AsyncThrowingStream<AgentChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let picked = try resolveBackend()

                    let memories = try await engram.recall(message, agentId: sphere)
                    let memoryBlock = formatMemoriesAsContext(memories)

                    let observedMessage = images.isEmpty
                        ? message
                        : "\(message) [shared \(images.count) image\(images.count > 1 ? "s" : "")]"
                    try await engram.observe(
                        agentId: sphere, content: "User: \(observedMessage)",
                        tags: ["conversation", "user"], salience: 0.6
                    )

                    // Tools are offered only when the chat is bound to a sphere:
                    // a registry without a sphereType would expose every tool
                    // (toolsFor(nil) is the "all" query), which sphere-less
                    // surfaces like the Meta Agent must not get.
                    let toolDefs: [LLMTool] = (tools != nil && sphereType != nil)
                        ? tools!.toolsFor(sphereType)
                        : []
                    let system = SpherePrompts.forSphere(
                        sphere,
                        userName: userName,
                        userContext: userContext,
                        memoryContext: memoryBlock,
                        hasTools: !toolDefs.isEmpty
                    )

                    var messages = history
                    if !message.isEmpty || !images.isEmpty {
                        messages.append(.user(message, images: images))
                    }

                    var fullResponse = ""
                    for _ in 0..<maxTurns {
                        var turnText = ""
                        var calls: [LLMToolCall] = []
                        var stopReason = StopReason.endTurn

                        for try await event in picked.engine.stream(
                            apiKey: picked.apiKey,
                            system: system,
                            messages: messages,
                            tools: toolDefs,
                            maxTokens: 1024
                        ) {
                            switch event {
                            case .textDelta(let text):
                                turnText += text
                                fullResponse += text
                                continuation.yield(.text(text))
                            case .toolCall(let call):
                                calls.append(call)
                            case .stop(let reason):
                                stopReason = reason
                            }
                        }

                        guard !calls.isEmpty, stopReason == .toolUse else { break }

                        messages.append(.assistant(turnText, toolCalls: calls))

                        var results: [LLMToolResult] = []
                        for call in calls {
                            guard let tools else {
                                results.append(LLMToolResult(
                                    toolCallId: call.id,
                                    content: JSONValue.object(["error": "no tool dispatcher"]).encodedString(),
                                    isError: true
                                ))
                                continuation.yield(.tool(confirmation: "Tool \(call.name) unavailable", isError: true))
                                continue
                            }
                            let execution = await tools.execute(call)
                            results.append(LLMToolResult(
                                toolCallId: call.id,
                                content: execution.content,
                                isError: execution.isError
                            ))
                            let label = tools.confirmation(for: call)
                            if execution.isError {
                                continuation.yield(.tool(confirmation: label ?? "Tool \(call.name) failed", isError: true))
                            } else if let label {
                                continuation.yield(.tool(confirmation: label, isError: false))
                            }
                        }
                        messages.append(.toolResults(results))
                    }

                    continuation.yield(.end)

                    if !fullResponse.isEmpty {
                        try await engram.observe(
                            agentId: sphere, content: "Assistant: \(fullResponse)",
                            tags: ["conversation", "agent"], salience: 0.8
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Meta agent

    /// Streams the daily brief from the Meta Agent, falling back to the last
    /// cached brief when offline.
    public func brief(calendarContext: String = "") -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let picked = try resolveBackend()

                    let memories = try await engram.crossAgentRecall(
                        "morning brief health sleep mood energy"
                    )
                    let memoryBlock = formatMemoriesAsContext(memories)
                    let contextBlock = [
                        calendarContext.isEmpty ? nil : "Calendar: \(calendarContext)",
                        memoryBlock.isEmpty ? nil : memoryBlock,
                    ].compactMap(\.self).joined(separator: "\n")

                    var buffer = ""
                    do {
                        for try await event in picked.engine.stream(
                            apiKey: picked.apiKey,
                            system: SpherePrompts.metaAgent(
                                extraContext: contextBlock.isEmpty ? "" : "\n\(contextBlock)"
                            ),
                            messages: [.user("Generate my morning brief across all life spheres.")],
                            tools: [],
                            maxTokens: 1024
                        ) {
                            switch event {
                            case .textDelta(let text):
                                buffer += text
                                continuation.yield(text)
                            case .stop:
                                break
                            case .toolCall:
                                break
                            }
                        }
                    } catch LLMError.backendUnavailable {
                        if buffer.isEmpty, let cached = await cache.loadBrief() {
                            continuation.yield(cached)
                            continuation.finish()
                            return
                        }
                        throw LLMError.backendUnavailable
                    }

                    if !buffer.isEmpty {
                        await cache.saveBrief(buffer)
                        try await engram.observe(
                            agentId: "meta", content: "Daily brief: \(buffer)",
                            tags: ["brief", "meta"], salience: 0.9
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streams a warm weekly reflection built from the digest facts, ending with
    /// one open question. Non-clinical, encouraging, and grounded in the data.
    public func weeklyNarrative(digest: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let picked = try resolveBackend()
                    let facts = digest.isEmpty
                        ? "A quiet week — not much was logged."
                        : digest.joined(separator: "\n")
                    let system = "You are a warm, concise life coach reviewing someone's week. "
                        + "Given the facts, write a short reflection of 3 to 4 sentences that "
                        + "connects the dots, then end with exactly one open, gentle question on "
                        + "its own line. No lists, no headers, no markdown. Ground every claim in "
                        + "the facts; never invent numbers."

                    var buffer = ""
                    for try await event in picked.engine.stream(
                        apiKey: picked.apiKey,
                        system: system,
                        messages: [.user("This week:\n\(facts)")],
                        tools: [],
                        maxTokens: 512
                    ) {
                        if case .textDelta(let text) = event {
                            buffer += text
                            continuation.yield(text)
                        }
                    }
                    if !buffer.isEmpty {
                        _ = try? await engram.observe(
                            agentId: "meta", content: "Weekly review: \(buffer)",
                            tags: ["review", "weekly", "meta"], salience: 0.85
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streams one of the agent-powered helper features. Each case supplies its
    /// own system role, user prompt, and (where useful) an Engram recall query,
    /// then reuses the same streaming + observe pipeline.
    public func assist(_ task: AgentTask) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let work = Task {
                do {
                    let picked = try resolveBackend()

                    var contextBlock = ""
                    if let query = task.recallQuery {
                        let memories = try await engram.crossAgentRecall(query)
                        contextBlock = formatMemoriesAsContext(memories)
                    }
                    let prompt = contextBlock.isEmpty
                        ? task.prompt
                        : "\(task.prompt)\n\nWhat I remember:\n\(contextBlock)"

                    var buffer = ""
                    for try await event in picked.engine.stream(
                        apiKey: picked.apiKey,
                        system: task.system,
                        messages: [.user(prompt)],
                        tools: [],
                        maxTokens: task.maxTokens
                    ) {
                        if case .textDelta(let text) = event {
                            buffer += text
                            continuation.yield(text)
                        }
                    }
                    if !buffer.isEmpty, let tag = task.observeTag {
                        _ = try? await engram.observe(
                            agentId: task.agentId, content: "\(tag.label): \(buffer)",
                            tags: tag.tags, salience: 0.8
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapError(error))
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    /// One-shot answer to a short question (e.g. a watch voice query). Concise
    /// by design — the reply is shown on a tiny screen.
    public func answer(_ question: String) async throws -> String {
        let picked = try resolveBackend()
        do {
            let text = try await picked.engine.complete(
                apiKey: picked.apiKey,
                system: SpherePrompts.metaAgent(
                    extraContext: "\nAnswer in one or two short sentences — this is read on a watch."
                ),
                prompt: question,
                maxTokens: 256
            )
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw Self.mapError(error)
        }
    }

    /// Fetches a single cross-sphere insight (non-streaming), falling back to
    /// the cached insight when offline.
    public func insight() async throws -> AgentInsight {
        let picked = try resolveBackend()

        let text: String
        do {
            text = try await picked.engine.complete(
                apiKey: picked.apiKey,
                system: SpherePrompts.metaAgent(),
                prompt: "Give me one sharp insight about my life patterns. "
                    + "Respond ONLY with valid JSON: {\"insight\":\"...\",\"tags\":[\"...\"]}",
                maxTokens: 512
            )
        } catch LLMError.backendUnavailable {
            if let cached = await cache.loadInsight() { return cached }
            throw AgentError.backendUnavailable
        } catch {
            throw Self.mapError(error)
        }

        // The model is asked for bare JSON but may wrap it in prose; extract
        // the outermost object before parsing.
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"),
           start < end,
           let json = JSONValue.decoded(from: String(text[start...end])) {
            let result = AgentInsight(
                insight: json["insight"]?.stringValue ?? text,
                tags: json["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []
            )
            await cache.saveInsight(result)
            return result
        }
        let fallback = AgentInsight(insight: text, tags: ["Meta Agent"])
        await cache.saveInsight(fallback)
        return fallback
    }

    // MARK: - Helpers

    private static func mapError(_ error: any Error) -> any Error {
        switch error {
        case LLMError.backendUnavailable: AgentError.backendUnavailable
        case LLMError.api(let message): AgentError.api(message)
        default: error
        }
    }
}

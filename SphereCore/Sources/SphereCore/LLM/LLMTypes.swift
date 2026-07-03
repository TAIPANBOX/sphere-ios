import Foundation

public struct LLMImage: Sendable, Equatable {
    public let mimeType: String
    public let base64Data: String

    public init(mimeType: String, base64Data: String) {
        self.mimeType = mimeType
        self.base64Data = base64Data
    }
}

public struct LLMToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public let input: JSONValue

    public init(id: String, name: String, input: JSONValue) {
        self.id = id
        self.name = name
        self.input = input
    }
}

public struct LLMToolResult: Sendable, Equatable {
    public let toolCallId: String
    public let content: String
    public let isError: Bool

    public init(toolCallId: String, content: String, isError: Bool = false) {
        self.toolCallId = toolCallId
        self.content = content
        self.isError = isError
    }
}

/// A unified message representation across engines.
///
/// Tool responses are represented as a `user` message carrying `toolResults`
/// (Anthropic shape) — each engine translates to what its API expects.
public struct LLMMessage: Sendable, Equatable {
    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public var role: Role
    public var text: String
    public var images: [LLMImage]
    public var toolCalls: [LLMToolCall]
    public var toolResults: [LLMToolResult]

    public init(
        role: Role,
        text: String = "",
        images: [LLMImage] = [],
        toolCalls: [LLMToolCall] = [],
        toolResults: [LLMToolResult] = []
    ) {
        self.role = role
        self.text = text
        self.images = images
        self.toolCalls = toolCalls
        self.toolResults = toolResults
    }

    public static func user(_ text: String, images: [LLMImage] = []) -> LLMMessage {
        LLMMessage(role: .user, text: text, images: images)
    }

    public static func assistant(_ text: String, toolCalls: [LLMToolCall] = []) -> LLMMessage {
        LLMMessage(role: .assistant, text: text, toolCalls: toolCalls)
    }

    public static func toolResults(_ results: [LLMToolResult]) -> LLMMessage {
        LLMMessage(role: .user, toolResults: results)
    }
}

public struct LLMTool: Sendable, Equatable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public enum StopReason: Sendable, Equatable {
    case endTurn
    case toolUse
    case maxTokens
    case other(String)

    init(anthropic raw: String?) {
        switch raw {
        case "tool_use": self = .toolUse
        case "max_tokens": self = .maxTokens
        case "end_turn", nil: self = .endTurn
        case .some(let value): self = .other(value)
        }
    }

    init(openAIFinishReason raw: String?) {
        switch raw {
        case "tool_calls": self = .toolUse
        case "length": self = .maxTokens
        case "stop", nil: self = .endTurn
        case .some(let value): self = .other(value)
        }
    }
}

public enum LLMEvent: Sendable, Equatable {
    case textDelta(String)
    case toolCall(LLMToolCall)
    case stop(StopReason)
}

public enum LLMError: Error, Equatable, Sendable {
    /// Connection-level failure (offline, DNS, timeout) — retryable, and the
    /// caller may fall back to cached content.
    case backendUnavailable
    /// The API returned an error response (bad key, quota, invalid request).
    case api(String)
}

/// One streaming LLM backend. Two implementations cover all four user-facing
/// providers: ``AnthropicEngine`` and ``OpenAICompatibleEngine``.
public protocol LLMEngine: Sendable {
    func stream(
        apiKey: String,
        system: String,
        messages: [LLMMessage],
        tools: [LLMTool],
        maxTokens: Int
    ) -> AsyncThrowingStream<LLMEvent, Error>

    func complete(
        apiKey: String,
        system: String,
        prompt: String,
        maxTokens: Int
    ) async throws -> String
}

extension LLMEngine {
    public func stream(
        apiKey: String,
        system: String,
        messages: [LLMMessage],
        tools: [LLMTool] = [],
        maxTokens: Int = 1024
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        stream(apiKey: apiKey, system: system, messages: messages, tools: tools, maxTokens: maxTokens)
    }

    public func complete(
        apiKey: String,
        system: String,
        prompt: String,
        maxTokens: Int = 512
    ) async throws -> String {
        try await complete(apiKey: apiKey, system: system, prompt: prompt, maxTokens: maxTokens)
    }
}

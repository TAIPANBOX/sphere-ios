import Foundation

/// One agent-invocable action or lookup, registered by a sphere store.
///
/// Unlike the Flutter version (which bound handlers to Riverpod providers),
/// handlers here are injected closures — each sphere store contributes its
/// tools at composition time, and the registry stays store-agnostic.
public struct SphereTool: Sendable {
    public let definition: LLMTool
    public let spheres: Set<SphereType>

    /// Read-only lookups run silently — no confirmation chip in the chat,
    /// since nothing was changed.
    public let silent: Bool

    /// Human-readable confirmation for the chat chip. Ignored for silent
    /// tools; nil falls back to "Done: <name>".
    public let confirmation: (@Sendable (JSONValue) -> String)?

    /// Executes the tool and returns the JSON string the model sees back.
    public let handler: @Sendable (JSONValue) async throws -> String

    public init(
        definition: LLMTool,
        spheres: Set<SphereType> = [],
        silent: Bool = false,
        confirmation: (@Sendable (JSONValue) -> String)? = nil,
        handler: @escaping @Sendable (JSONValue) async throws -> String
    ) {
        self.definition = definition
        self.spheres = spheres
        self.silent = silent
        self.confirmation = confirmation
        self.handler = handler
    }
}

public struct SphereToolExecution: Sendable, Equatable {
    public let content: String
    public let isError: Bool
}

public struct SphereToolRegistry: Sendable {
    private let tools: [SphereTool]

    public init(tools: [SphereTool]) {
        self.tools = tools
    }

    /// Tool definitions offered to the model for `sphere` (tools without a
    /// sphere set are offered everywhere; nil returns everything).
    public func toolsFor(_ sphere: SphereType?) -> [LLMTool] {
        tools
            .filter { sphere == nil || $0.spheres.isEmpty || $0.spheres.contains(sphere!) }
            .map(\.definition)
    }

    public func execute(_ call: LLMToolCall) async -> SphereToolExecution {
        guard let tool = tools.first(where: { $0.definition.name == call.name }) else {
            return SphereToolExecution(
                content: JSONValue.object(["error": .string("Unknown tool: \(call.name)")]).encodedString(),
                isError: true
            )
        }
        do {
            return SphereToolExecution(content: try await tool.handler(call.input), isError: false)
        } catch {
            return SphereToolExecution(
                content: JSONValue.object(["error": .string("\(error)")]).encodedString(),
                isError: true
            )
        }
    }

    /// Chat-chip label for `call`, or nil for silent/unknown tools.
    public func confirmation(for call: LLMToolCall) -> String? {
        guard let tool = tools.first(where: { $0.definition.name == call.name }),
              !tool.silent
        else { return nil }
        return tool.confirmation?(call.input) ?? "Done: \(call.name)"
    }
}

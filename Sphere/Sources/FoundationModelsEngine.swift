import Foundation
import SphereCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Version-agnostic entry point for the free on-device backend. Callable from
/// any iOS version; returns an engine only when Apple's Foundation Models
/// system model is present and ready (iPhone 15 Pro+ / iOS 26 with Apple
/// Intelligence enabled), else nil so the agent falls back to a cloud key or
/// the keyless state.
enum OnDeviceAI {
    static func makeEngineIfAvailable() -> (any LLMEngine)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return FoundationModelsEngine.makeIfAvailable()
        }
        #endif
        return nil
    }

    static var isAvailable: Bool { makeEngineIfAvailable() != nil }
}

#if canImport(FoundationModels)

/// Streams from Apple's on-device model. v1 is text-only — it ignores `tools`
/// (no on-device tool calling yet) and emits text deltas then `.endTurn`. The
/// daily brief and conversational chat work fully; tool-driven logging routes
/// through the rule-based quick-capture path or a cloud key.
@available(iOS 26.0, *)
struct FoundationModelsEngine: LLMEngine {
    static func makeIfAvailable() -> FoundationModelsEngine? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        return FoundationModelsEngine()
    }

    func stream(
        apiKey: String,
        system: String,
        messages: [LLMMessage],
        tools: [LLMTool],
        maxTokens: Int
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        let prompt = Self.render(messages)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: system)
                    var delivered = ""
                    for try await partial in session.streamResponse(to: prompt) {
                        let full = partial.content
                        if full.count > delivered.count {
                            continuation.yield(.textDelta(String(full.dropFirst(delivered.count))))
                            delivered = full
                        }
                    }
                    continuation.yield(.stop(.endTurn))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: LLMError.api(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func complete(apiKey: String, system: String, prompt: String, maxTokens: Int) async throws -> String {
        let session = LanguageModelSession(instructions: system)
        do {
            return try await session.respond(to: prompt).content
        } catch {
            throw LLMError.api(error.localizedDescription)
        }
    }

    /// Renders the conversation into one prompt (system goes in as session
    /// instructions). Text-only, so images and tool results are dropped.
    private static func render(_ messages: [LLMMessage]) -> String {
        messages
            .map { message in
                switch message.role {
                case .user: message.text
                case .assistant: "Assistant: \(message.text)"
                }
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

#endif

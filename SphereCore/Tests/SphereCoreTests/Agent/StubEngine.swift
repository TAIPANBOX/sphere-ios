import Foundation
@testable import SphereCore

/// Scripted engine: each `stream` call plays the next event list; every call
/// is recorded so tests can assert what the service actually sent.
final class StubEngine: LLMEngine, @unchecked Sendable {
    struct Call {
        let system: String
        let messages: [LLMMessage]
        let tools: [LLMTool]
        let maxTokens: Int
    }

    struct CompleteCall {
        let system: String
        let prompt: String
        let maxTokens: Int
    }

    private let lock = NSLock()
    private var scripts: [[LLMEvent]]
    private var _calls: [Call] = []
    private var _completeCalls: [CompleteCall] = []

    var streamError: LLMError?
    var completeResult = ""
    var completeError: LLMError?

    init(scripts: [[LLMEvent]] = []) {
        self.scripts = scripts
    }

    var calls: [Call] {
        lock.withLock { _calls }
    }

    var completeCalls: [CompleteCall] {
        lock.withLock { _completeCalls }
    }

    func stream(
        apiKey: String,
        system: String,
        messages: [LLMMessage],
        tools: [LLMTool],
        maxTokens: Int
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        let events: [LLMEvent] = lock.withLock {
            _calls.append(Call(system: system, messages: messages, tools: tools, maxTokens: maxTokens))
            return scripts.isEmpty ? [] : scripts.removeFirst()
        }
        let error = streamError
        return AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func complete(
        apiKey: String,
        system: String,
        prompt: String,
        maxTokens: Int
    ) async throws -> String {
        lock.withLock {
            _completeCalls.append(CompleteCall(system: system, prompt: prompt, maxTokens: maxTokens))
        }
        if let completeError { throw completeError }
        return completeResult
    }
}

import Foundation

/// Source of the user's provider API keys. The app wires a Keychain-backed
/// implementation; tests and previews use ``InMemoryAPIKeyStore``.
public protocol APIKeyStore: Sendable {
    func key(for provider: LLMProviderID) -> String?
}

public final class InMemoryAPIKeyStore: APIKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [LLMProviderID: String]

    public init(_ keys: [LLMProviderID: String] = [:]) {
        self.keys = keys
    }

    public func key(for provider: LLMProviderID) -> String? {
        lock.withLock { keys[provider] }
    }

    public func set(_ key: String?, for provider: LLMProviderID) {
        lock.withLock { keys[provider] = key }
    }
}

#if canImport(Security)
import Foundation
import Security

/// Keychain-backed provider keys. Items are marked synchronizable so keys
/// follow the user's iCloud Keychain to new devices (plan decision).
///
/// Not unit-tested: SecItem requires app entitlements absent in `swift test`;
/// exercised via the app target. Tests use ``InMemoryAPIKeyStore``.
public final class KeychainAPIKeyStore: APIKeyStore, @unchecked Sendable {
    private let service: String

    public init(service: String = "app.sphere.ai-keys") {
        self.service = service
    }

    public func key(for provider: LLMProviderID) -> String? {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ key: String?, for provider: LLMProviderID) {
        let query = baseQuery(for: provider)
        SecItemDelete(query as CFDictionary)

        guard let key, !key.isEmpty else { return }
        var attributes = query
        // ...Any is a query-only wildcard; stored items must say true.
        attributes[kSecAttrSynchronizable as String] = true
        attributes[kSecValueData as String] = Data(key.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func baseQuery(for provider: LLMProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }
}
#endif

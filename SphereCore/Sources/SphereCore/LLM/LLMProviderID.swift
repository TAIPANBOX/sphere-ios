import Foundation

/// Which backend answers the agents. On-device (Apple Foundation Models) is
/// the free, no-key default; a downloaded Tier-1 model is the free path for
/// devices without Apple Intelligence; OpenRouter is the optional cloud tier.
public enum AIBackend: Equatable, Hashable, Sendable {
    case onDevice
    /// The active model downloaded via the model manager (AI Tier 1). Which
    /// model is active lives in `ModelManager`; the engine is injected by the
    /// app target.
    case localModel
    case cloud(LLMProviderID)

    public var label: String {
        switch self {
        case .onDevice: "On-device (free)"
        case .localModel: "Downloaded model"
        case .cloud(let provider): provider.displayName
        }
    }

    /// Stable string for @AppStorage / UserDefaults persistence.
    public var storageValue: String {
        switch self {
        case .onDevice: "onDevice"
        case .localModel: "localModel"
        case .cloud(let provider): provider.rawValue
        }
    }

    public init?(storageValue: String) {
        if storageValue == "onDevice" {
            self = .onDevice
        } else if storageValue == "localModel" {
            self = .localModel
        } else if let provider = LLMProviderID(rawValue: storageValue) {
            self = .cloud(provider)
        } else {
            return nil
        }
    }
}

/// The single cloud provider. One OpenRouter key gives access to every hosted
/// model (Claude, GPT, Gemini, …) through the OpenAI-compatible API, so the
/// app never talks to vendor APIs directly.
public enum LLMProviderID: String, CaseIterable, Codable, Sendable {
    case openrouter

    public var displayName: String {
        switch self {
        case .openrouter: "OpenRouter"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openrouter: "anthropic/claude-haiku-4.5"
        }
    }

    /// Cheap format check for a pasted key, used to gate key-dependent UI
    /// (e.g. the cloud-model picker). Not a network validation — just enough
    /// to reject obvious non-keys. OpenRouter keys look like
    /// `sk-or-v1-<64 hex>`; we require the stable `sk-or-` prefix, a sane
    /// length, and the key charset, without pinning the version suffix.
    public func isPlausibleKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .openrouter:
            guard trimmed.hasPrefix("sk-or-"), trimmed.count >= 24 else { return false }
            return trimmed.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        }
    }

    public func makeEngine(
        model: String? = nil,
        transport: any LLMTransport = URLSessionTransport()
    ) -> any LLMEngine {
        let model = model ?? defaultModel
        switch self {
        case .openrouter:
            return OpenAICompatibleEngine(
                baseURL: URL(string: "https://openrouter.ai/api/v1")!,
                model: model,
                extraHeaders: [
                    "HTTP-Referer": "https://sphere.app",
                    "X-Title": "Sphere",
                ],
                transport: transport
            )
        }
    }
}

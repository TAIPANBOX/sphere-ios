import Foundation

/// Which backend answers the agents. On-device (Apple Foundation Models) is
/// the free, no-key default; a downloaded Tier-1 model is the free path for
/// devices without Apple Intelligence; the four cloud providers are the
/// optional power tier.
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

/// The four user-facing AI providers. Anthropic gets the native engine;
/// OpenAI, Gemini, and OpenRouter all ride ``OpenAICompatibleEngine`` with
/// their own base URL, default model, and headers.
public enum LLMProviderID: String, CaseIterable, Codable, Sendable {
    case anthropic
    case openai
    case gemini
    case openrouter

    public var displayName: String {
        switch self {
        case .anthropic: "Claude"
        case .openai: "ChatGPT"
        case .gemini: "Gemini"
        case .openrouter: "OpenRouter"
        }
    }

    public var defaultModel: String {
        switch self {
        case .anthropic: "claude-haiku-4-5"
        case .openai: "gpt-5-mini"
        case .gemini: "gemini-2.5-flash"
        case .openrouter: "anthropic/claude-haiku-4.5"
        }
    }

    public func makeEngine(
        model: String? = nil,
        transport: any LLMTransport = URLSessionTransport()
    ) -> any LLMEngine {
        let model = model ?? defaultModel
        switch self {
        case .anthropic:
            return AnthropicEngine(model: model, transport: transport)
        case .openai:
            return OpenAICompatibleEngine(
                baseURL: URL(string: "https://api.openai.com/v1")!,
                model: model,
                transport: transport
            )
        case .gemini:
            return OpenAICompatibleEngine(
                baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!,
                model: model,
                transport: transport
            )
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

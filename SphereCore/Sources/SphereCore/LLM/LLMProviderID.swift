import Foundation

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

import Foundation

/// One downloadable on-device model and the metadata the manager needs to show
/// size / RAM-fit badges and route a download.
public struct ModelInfo: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let family: String
    public let paramsB: Double
    public let quant: String
    /// Download size in megabytes.
    public let sizeMB: Int
    /// Runtime memory the model needs to load and run.
    public let minRAMMB: Int
    public let contextTokens: Int
    public let url: String

    public init(
        id: String, name: String, family: String, paramsB: Double, quant: String,
        sizeMB: Int, minRAMMB: Int, contextTokens: Int, url: String
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.paramsB = paramsB
        self.quant = quant
        self.sizeMB = sizeMB
        self.minRAMMB = minRAMMB
        self.contextTokens = contextTokens
        self.url = url
    }
}

/// The curated Tier-1 models (EXPANSION_PLAN §9.1). Small, 4-bit, on-device.
public enum ModelCatalog {
    public static let all: [ModelInfo] = [
        ModelInfo(
            id: "smollm2-1.7b-q4", name: "SmolLM2 1.7B", family: "SmolLM2",
            paramsB: 1.7, quant: "Q4", sizeMB: 1_000, minRAMMB: 1_500, contextTokens: 8_192,
            url: "https://huggingface.co/mlx-community/SmolLM2-1.7B-Instruct-4bit"
        ),
        ModelInfo(
            id: "qwen2.5-1.5b-q4", name: "Qwen2.5 1.5B", family: "Qwen",
            paramsB: 1.5, quant: "Q4", sizeMB: 1_000, minRAMMB: 1_500, contextTokens: 32_768,
            url: "https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit"
        ),
        ModelInfo(
            id: "gemma-2-2b-q4", name: "Gemma 2 2B", family: "Gemma",
            paramsB: 2.6, quant: "Q4", sizeMB: 1_600, minRAMMB: 2_400, contextTokens: 8_192,
            url: "https://huggingface.co/mlx-community/gemma-2-2b-it-4bit"
        ),
        ModelInfo(
            id: "llama-3.2-3b-q4", name: "Llama 3.2 3B", family: "Llama",
            paramsB: 3.2, quant: "Q4", sizeMB: 2_000, minRAMMB: 3_000, contextTokens: 131_072,
            url: "https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit"
        ),
        ModelInfo(
            id: "phi-3.5-mini-q4", name: "Phi-3.5 mini", family: "Phi",
            paramsB: 3.8, quant: "Q4", sizeMB: 2_300, minRAMMB: 3_500, contextTokens: 131_072,
            url: "https://huggingface.co/mlx-community/Phi-3.5-mini-instruct-4bit"
        ),
    ]

    public static func model(id: String) -> ModelInfo? {
        all.first { $0.id == id }
    }
}

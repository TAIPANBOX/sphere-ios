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

    /// Hugging Face repo id (e.g. "mlx-community/Qwen2.5-1.5B-Instruct-4bit"),
    /// derived from the catalog URL — what the MLX hub loader takes.
    public var hubID: String {
        url.replacingOccurrences(of: "https://huggingface.co/", with: "")
    }
}

/// The curated Tier-1 models (EXPANSION_PLAN §9.1). Deliberately small only
/// (≤ ~2.6B params, ≤ 1.6 GB download): they fit every supported device and
/// keep the download respectful of storage and cellular data.
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
    ]

    public static func model(id: String) -> ModelInfo? {
        all.first { $0.id == id }
    }
}

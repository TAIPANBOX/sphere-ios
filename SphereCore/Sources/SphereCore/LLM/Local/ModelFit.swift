import Foundation

/// How well a model fits the device's memory.
public enum RAMFit: String, Sendable {
    case comfortable, tight, insufficient

    public var label: String {
        switch self {
        case .comfortable: "Runs well"
        case .tight: "May be slow"
        case .insufficient: "Not enough memory"
        }
    }
}

/// Pure size / RAM / disk fit checks for the model manager.
public enum ModelFit {
    /// `comfortable` with ≥2× headroom over the model's need, `tight` when it
    /// merely fits, else `insufficient`.
    public static func ramFit(model: ModelInfo, deviceRAMMB: Int) -> RAMFit {
        if deviceRAMMB >= model.minRAMMB * 2 { return .comfortable }
        if deviceRAMMB >= model.minRAMMB { return .tight }
        return .insufficient
    }

    /// Needs the download size plus a safety margin of free disk.
    public static func fitsOnDisk(model: ModelInfo, freeDiskMB: Int, marginMB: Int = 300) -> Bool {
        freeDiskMB >= model.sizeMB + marginMB
    }

    /// Human size, e.g. "1.0 GB" or "620 MB".
    public static func sizeLabel(_ model: ModelInfo) -> String {
        sizeLabel(megabytes: model.sizeMB)
    }

    public static func sizeLabel(megabytes: Int) -> String {
        if megabytes >= 1_000 {
            return String(format: "%.1f GB", Double(megabytes) / 1_000)
        }
        return "\(megabytes) MB"
    }
}

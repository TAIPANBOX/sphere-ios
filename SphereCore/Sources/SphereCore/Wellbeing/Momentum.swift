import Foundation

/// A warm "becoming" band, shown alongside (or instead of) a cold percentage —
/// the Finch/Atoms lesson that momentum motivates where a bare % doesn't. Pairs
/// with forgiveness (streaks that bridge excused days).
public enum MomentumBand: Int, Sendable, Comparable, CaseIterable {
    case dormant, starting, building, rolling, thriving

    public static func < (a: MomentumBand, b: MomentumBand) -> Bool { a.rawValue < b.rawValue }

    public var emoji: String {
        switch self {
        case .dormant: "🌱"
        case .starting: "🌿"
        case .building: "📈"
        case .rolling: "🔥"
        case .thriving: "⭐️"
        }
    }
}

public enum Momentum {
    /// Momentum from a habit streak (days), forgiveness already applied upstream.
    public static func forStreak(_ days: Int) -> MomentumBand {
        switch days {
        case ..<1: .dormant
        case 1...2: .starting
        case 3...6: .building
        case 7...20: .rolling
        default: .thriving
        }
    }

    /// Warm streak phrase, e.g. "On a roll · 9 days".
    public static func streakPhrase(_ days: Int) -> String {
        let band = forStreak(days)
        let label: String
        switch band {
        case .dormant: label = "Start today"
        case .starting: label = "Getting going"
        case .building: label = "Building momentum"
        case .rolling: label = "On a roll"
        case .thriving: label = "Unstoppable"
        }
        guard days > 0 else { return label }
        return "\(label) · \(days) day\(days == 1 ? "" : "s")"
    }

    /// Momentum from a goal's progress percent (0–100).
    public static func forProgress(_ percent: Int) -> MomentumBand {
        switch percent {
        case ..<1: .dormant
        case 1...25: .starting
        case 26...60: .building
        case 61...90: .rolling
        default: .thriving
        }
    }

    /// Warm progress phrase that reframes the bare percentage.
    public static func progressPhrase(_ percent: Int) -> String {
        switch forProgress(percent) {
        case .dormant: "Not started — one small step is enough"
        case .starting: "Just beginning"
        case .building: "Building momentum"
        case .rolling: "Gaining ground"
        case .thriving: percent >= 100 ? "Done" : "Almost there"
        }
    }
}

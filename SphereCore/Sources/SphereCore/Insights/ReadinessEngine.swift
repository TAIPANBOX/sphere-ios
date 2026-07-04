import Foundation

public enum ReadinessBand: String, Codable, Sendable {
    case low, moderate, high
}

/// Everything the readiness verdict needs, gathered from Rest + Mindfulness.
public struct ReadinessInput: Sendable, Equatable {
    public var sleepHours: Double?
    public var sleepGoal: Double
    public var stress: Int?
    public var wakeHour: Int
    public var bedtimeHour: Int
    public var bedtimeMinute: Int
    /// Learned offset (points) nudging the raw score toward how the user
    /// actually reports feeling.
    public var correction: Double

    public init(
        sleepHours: Double?, sleepGoal: Double = 8, stress: Int? = nil,
        wakeHour: Int = 7, bedtimeHour: Int = 23, bedtimeMinute: Int = 0,
        correction: Double = 0
    ) {
        self.sleepHours = sleepHours
        self.sleepGoal = sleepGoal
        self.stress = stress
        self.wakeHour = wakeHour
        self.bedtimeHour = bedtimeHour
        self.bedtimeMinute = bedtimeMinute
        self.correction = correction
    }
}

/// The single adaptive "Today" line — Bevel's readiness meets RISE's energy
/// schedule, self-correcting on the user's felt-energy ratings.
public struct ReadinessVerdict: Sendable, Equatable {
    public let score: Int
    public let band: ReadinessBand
    public let headline: String
    public let recommendation: String
    public let focusWindow: String
    public let windDown: String
}

public enum ReadinessEngine {
    /// Raw score 0–100 (the proven Rest formula: sleep vs goal → 60, low stress
    /// → 40, unknown stress → the neutral 20). Deliberately correction-free so
    /// the self-correction can learn its bias.
    public static func rawScore(sleepHours: Double?, sleepGoal: Double, stress: Int?) -> Int {
        let hours = sleepHours ?? 0
        let sleepPoints = Int((min(max(hours / max(sleepGoal, 1), 0), 1) * 60).rounded())
        let stressPoints = stress.map {
            Int((Double(10 - min(max($0, 0), 10)) / 10 * 40).rounded())
        } ?? 20
        return min(max(sleepPoints + stressPoints, 0), 100)
    }

    /// Offset (clamped to ±`cap`) = mean gap between how the user actually felt
    /// (energy 1–5 → 20–100) and what we predicted, over days with both. Needs
    /// at least `minDays` overlapping days, else 0 (no adaptation yet).
    public static func correction(
        predicted: [String: Int], felt: [String: Int], minDays: Int = 3, cap: Double = 15
    ) -> Double {
        let common = predicted.keys.filter { felt[$0] != nil }
        guard common.count >= minDays else { return 0 }
        let diffs = common.map { Double((felt[$0] ?? 0) * 20 - (predicted[$0] ?? 0)) }
        let mean = diffs.reduce(0, +) / Double(diffs.count)
        return min(max(mean, -cap), cap)
    }

    public static func verdict(_ input: ReadinessInput) -> ReadinessVerdict {
        let raw = rawScore(sleepHours: input.sleepHours, sleepGoal: input.sleepGoal, stress: input.stress)
        let score = min(max(Int((Double(raw) + input.correction).rounded()), 0), 100)
        let band: ReadinessBand = score >= 70 ? .high : (score >= 45 ? .moderate : .low)

        let (headline, recommendation): (String, String)
        switch band {
        case .high:
            headline = "You're well-recovered."
            recommendation = "A good day to push on something hard."
        case .moderate:
            headline = "Steady — a decent tank."
            recommendation = "Protect your focus window and don't overcommit."
        case .low:
            headline = "Running low today."
            recommendation = "Go gentle: one priority, and rest tonight."
        }

        return ReadinessVerdict(
            score: score, band: band, headline: headline, recommendation: recommendation,
            focusWindow: focusWindow(wakeHour: input.wakeHour, band: band),
            windDown: windDown(bedtimeHour: input.bedtimeHour, bedtimeMinute: input.bedtimeMinute)
        )
    }

    /// Peak-focus window: ~2 h after waking for a full window; when low, a
    /// shorter, slightly later block.
    static func focusWindow(wakeHour: Int, band: ReadinessBand) -> String {
        let start = band == .low ? wakeHour + 3 : wakeHour + 2
        let length = band == .low ? 1 : 2
        let end = start + length
        return "\(hourLabel(start))–\(hourLabel(end))"
    }

    /// Wind-down 30 minutes before the scheduled bedtime, in 24 h form.
    static func windDown(bedtimeHour: Int, bedtimeMinute: Int) -> String {
        var minutes = bedtimeHour * 60 + bedtimeMinute - 30
        minutes = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// 24 h hour → friendly 12 h label ("9 AM", "1 PM", "12 PM").
    static func hourLabel(_ hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        let meridiem = h < 12 ? "AM" : "PM"
        let twelve = h % 12 == 0 ? 12 : h % 12
        return "\(twelve) \(meridiem)"
    }
}

import Foundation

/// Hyper-parameters for the importance scoring formula, ported from the
/// reference Python Engram (`engram/importance.py`):
///
///     importance(m, t) =
///         salience * exp(-lambda * elapsed_days)
///       + alpha * log(1 + access_count)
///       + beta * emotional_valence
public struct DecayConfig: Sendable {
    /// Decay rate per day; the default gives a half-life of ~7 days.
    public var lambda: Double
    /// Reinforcement weight from access frequency.
    public var alpha: Double
    /// Emotional weight.
    public var beta: Double
    /// Minimum importance before a memory becomes prunable.
    public var threshold: Double

    public init(
        lambda: Double = 0.1,
        alpha: Double = 0.2,
        beta: Double = 0.1,
        threshold: Double = 0.1
    ) {
        self.lambda = lambda
        self.alpha = alpha
        self.beta = beta
        self.threshold = threshold
    }

    /// Importance of a memory at `now`, given its stats.
    /// `elapsedDays` is clamped at 0 so clock skew cannot inflate the decay term.
    public func importance(
        salience: Double,
        emotionalValence: Double,
        lastAccess: Date,
        accessCount: Int,
        now: Date
    ) -> Double {
        let elapsedDays = max(0, now.timeIntervalSince(lastAccess) / 86_400)
        let decayTerm = salience * exp(-lambda * elapsedDays)
        let accessTerm = alpha * log1p(Double(accessCount))
        let emotionTerm = beta * emotionalValence
        return decayTerm + accessTerm + emotionTerm
    }
}

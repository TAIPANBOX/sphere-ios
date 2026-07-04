import Foundation

/// A day-keyed metric series (dateKey → value), the input to the correlation
/// engine. `displayName` is the human label used in insight phrasing.
public struct DailySeries: Sendable, Equatable {
    public let metricID: String
    public let displayName: String
    public let values: [String: Double]

    public init(metricID: String, displayName: String, values: [String: Double]) {
        self.metricID = metricID
        self.displayName = displayName
        self.values = values
    }
}

/// One discovered relationship between two metrics.
public struct Correlation: Sendable, Equatable {
    public let metricA: String
    public let metricB: String
    /// Pearson r in [-1, 1].
    public let r: Double
    /// Overlapping day-pairs the correlation is based on.
    public let n: Int
    /// 0 = same day; L>0 = A on a day vs B `L` days later.
    public let lagDays: Int
    public let phrase: String

    public var strength: Double { abs(r) }
}

/// Cross-sphere correlation engine (N2) — the moat. Pearson r over aligned
/// day-pairs, plus a one-day-lag variant, across every day-keyed metric the
/// spheres record. Reports only relationships strong and well-sampled enough
/// to be worth mentioning, phrased non-causally.
public enum CorrelationEngine {
    public static let minOverlap = 10
    public static let minR = 0.3
    public static let maxLag = 1

    /// Pearson correlation of paired samples; nil when undefined (constant
    /// series or too few points).
    public static func pearson(_ pairs: [(Double, Double)]) -> Double? {
        let n = pairs.count
        guard n >= 2 else { return nil }
        let count = Double(n)
        let meanX = pairs.reduce(0) { $0 + $1.0 } / count
        let meanY = pairs.reduce(0) { $0 + $1.1 } / count
        var covariance = 0.0, varX = 0.0, varY = 0.0
        for (x, y) in pairs {
            let dx = x - meanX, dy = y - meanY
            covariance += dx * dy
            varX += dx * dx
            varY += dy * dy
        }
        guard varX > 0, varY > 0 else { return nil }
        return covariance / (varX.squareRoot() * varY.squareRoot())
    }

    /// Pairs `a`'s value on day D with `b`'s value on day D+lag.
    static func alignedPairs(_ a: DailySeries, _ b: DailySeries, lag: Int) -> [(Double, Double)] {
        a.values.compactMap { key, aValue in
            let bKey = lag == 0 ? key : DayKey.shift(key, byDays: lag)
            guard let bKey, let bValue = b.values[bKey] else { return nil }
            return (aValue, bValue)
        }
    }

    /// All correlations above threshold, strongest first. Same-day pairs are
    /// computed once per unordered pair; lag pairs once per ordered pair.
    public static func correlations(_ series: [DailySeries]) -> [Correlation] {
        var results: [Correlation] = []
        for i in series.indices {
            for j in series.indices where j > i {
                if let c = correlation(series[i], series[j], lag: 0) { results.append(c) }
            }
        }
        if maxLag >= 1 {
            for lag in 1...maxLag {
                for a in series {
                    for b in series where b.metricID != a.metricID {
                        if let c = correlation(a, b, lag: lag) { results.append(c) }
                    }
                }
            }
        }
        return results.sorted { $0.strength > $1.strength }
    }

    private static func correlation(_ a: DailySeries, _ b: DailySeries, lag: Int) -> Correlation? {
        let pairs = alignedPairs(a, b, lag: lag)
        guard pairs.count >= minOverlap, let r = pearson(pairs), abs(r) >= minR else { return nil }
        return Correlation(
            metricA: a.displayName, metricB: b.displayName, r: r, n: pairs.count,
            lagDays: lag, phrase: phrase(a: a.displayName, b: b.displayName, r: r, lag: lag)
        )
    }

    /// Deliberately non-causal wording ("tends to", not "causes").
    static func phrase(a: String, b: String, r: Double, lag: Int) -> String {
        let direction = r > 0 ? "higher" : "lower"
        if lag == 0 {
            return "On days your \(a.lowercased()) is higher, your \(b.lowercased()) tends to be \(direction)."
        }
        return "After a day of higher \(a.lowercased()), your \(b.lowercased()) tends to be \(direction) the next day."
    }
}

import Foundation
import GRDB

public enum ReviewType: String, Codable, CaseIterable, Sendable {
    case weekly, monthly, lifeWheel
}

/// A saved reflection — a weekly/monthly narrative or a Life Wheel snapshot.
public struct Review: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var type: ReviewType
    /// Period identifier (e.g. an ISO week key or "2026-Q3").
    public var periodKey: String
    public var content: String
    /// Sphere → self-rating (1–10), for Life Wheel reviews.
    public var selfRatings: [String: Int]
    public var createdAt: Date

    public init(
        id: String, type: ReviewType, periodKey: String, content: String = "",
        selfRatings: [String: Int] = [:], createdAt: Date
    ) {
        self.id = id
        self.type = type
        self.periodKey = periodKey
        self.content = content
        self.selfRatings = selfRatings
        self.createdAt = createdAt
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("review", now: now) }
}

extension Review: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "reviews"
}

/// The gap between how you *feel* about a sphere and what your data *says*.
public struct WheelDelta: Sendable, Equatable {
    public let sphere: SphereType
    /// Self-rating scaled to 0–100 (rating × 10).
    public let feeling: Int
    /// Computed Life Score for the sphere (0–100).
    public let data: Int
    /// feeling − data; negative = you feel worse than the numbers say.
    public var delta: Int { feeling - data }
}

/// Pure Life Wheel comparison (N6): self-ratings vs the computed Life Score.
public enum LifeWheel {
    /// Deltas for every sphere that has both a self-rating (1–10) and a
    /// computed score, sorted by widest gap first.
    public static func deltas(
        selfRatings: [SphereType: Int], computed: [SphereType: Int]
    ) -> [WheelDelta] {
        selfRatings.compactMap { sphere, rating -> WheelDelta? in
            guard let score = computed[sphere] else { return nil }
            return WheelDelta(sphere: sphere, feeling: rating * 10, data: score)
        }
        .sorted { abs($0.delta) > abs($1.delta) }
    }

    /// A one-line insight from the widest gap, or nil when nothing stands out.
    public static func insight(_ deltas: [WheelDelta], minGap: Int = 20) -> String? {
        guard let top = deltas.first, abs(top.delta) >= minGap else { return nil }
        let name = top.sphere.rawValue.capitalized
        return top.delta < 0
            ? "You feel worse about \(name) than your data suggests — worth a closer look."
            : "You feel better about \(name) than the numbers show — nice."
    }
}

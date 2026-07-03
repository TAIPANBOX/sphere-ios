import Foundation
import GRDB

public enum GoalHorizon: String, Codable, CaseIterable, Sendable {
    case month
    case quarter
    case year
    case threeYears

    public var label: String {
        switch self {
        case .month: "1 month"
        case .quarter: "3 months"
        case .year: "1 year"
        case .threeYears: "3 years"
        }
    }
}

public enum GoalStatus: String, Codable, CaseIterable, Sendable {
    case active
    case completed
    case paused
}

public struct Goal: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var description: String
    public var emoji: String
    public var horizon: GoalHorizon
    public var status: GoalStatus
    /// 0–100
    public var progressPercent: Int
    public var keyResults: [String]
    public var sphereType: SphereType?
    public var blockedByGoalId: String?

    public init(
        id: String,
        title: String,
        description: String = "",
        emoji: String = "🎯",
        horizon: GoalHorizon = .year,
        status: GoalStatus = .active,
        progressPercent: Int = 0,
        keyResults: [String] = [],
        sphereType: SphereType? = nil,
        blockedByGoalId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.emoji = emoji
        self.horizon = horizon
        self.status = status
        self.progressPercent = progressPercent
        self.keyResults = keyResults
        self.sphereType = sphereType
        self.blockedByGoalId = blockedByGoalId
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("goal", now: now)
    }
}

extension Goal: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "goals"
}

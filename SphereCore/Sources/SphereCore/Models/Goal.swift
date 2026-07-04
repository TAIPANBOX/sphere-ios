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
    /// The reason this matters — resurfaced when the goal stalls.
    public var why: String

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
        blockedByGoalId: String? = nil,
        why: String = ""
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
        self.why = why
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("goal", now: now)
    }
}

extension Goal: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "goals"
}

/// Something to deliberately say no to — a boundary, not a target. Clarity on
/// what you won't do frees focus for what you will.
public struct AntiGoal: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var note: String

    public init(id: String, title: String, note: String = "") {
        self.id = id
        self.title = title
        self.note = note
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("antigoal", now: now) }
}

extension AntiGoal: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "anti_goals"
}

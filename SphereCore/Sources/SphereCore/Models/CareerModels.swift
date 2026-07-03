import Foundation
import GRDB

public enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case low, medium, high, urgent

    public var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }

    public var emoji: String {
        switch self {
        case .low: "🟢"
        case .medium: "🟡"
        case .high: "🟠"
        case .urgent: "🔴"
        }
    }
}

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case todo, inProgress, done
}

public struct CareerTask: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var project: String
    public var priority: TaskPriority
    public var status: TaskStatus
    public var dueDate: Date?
    public var createdAt: Date

    public init(
        id: String,
        title: String,
        project: String = "",
        priority: TaskPriority = .medium,
        status: TaskStatus = .todo,
        dueDate: Date? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.priority = priority
        self.status = status
        self.dueDate = dueDate
        self.createdAt = createdAt
    }

    public func isOverdue(asOf now: Date = Date()) -> Bool {
        guard let dueDate, status != .done else { return false }
        return dueDate < now
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("task", now: now)
    }
}

extension CareerTask: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "career_tasks"
}

public enum ProjectStatus: String, Codable, CaseIterable, Sendable {
    case active, onHold, completed

    public var label: String {
        switch self {
        case .active: "Active"
        case .onHold: "On Hold"
        case .completed: "Completed"
        }
    }

    public var emoji: String {
        switch self {
        case .active: "🚀"
        case .onHold: "⏸️"
        case .completed: "✅"
        }
    }
}

public struct CareerProject: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var role: String
    /// 0–100
    public var progressPercent: Int
    public var status: ProjectStatus
    public var deadline: Date?
    public var note: String

    public init(
        id: String,
        name: String,
        role: String = "",
        progressPercent: Int = 0,
        status: ProjectStatus = .active,
        deadline: Date? = nil,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.progressPercent = progressPercent
        self.status = status
        self.deadline = deadline
        self.note = note
    }

    public func daysRemaining(asOf now: Date = Date()) -> Int? {
        guard let deadline else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: deadline)
        ).day
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("proj", now: now)
    }
}

extension CareerProject: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "career_projects"
}

public enum InterviewStatus: String, Codable, CaseIterable, Sendable {
    case applied, screening, interview, offer, rejected, accepted

    public var label: String {
        switch self {
        case .applied: "Applied"
        case .screening: "Screening"
        case .interview: "Interview"
        case .offer: "Offer"
        case .rejected: "Rejected"
        case .accepted: "Accepted"
        }
    }

    public var emoji: String {
        switch self {
        case .applied: "📨"
        case .screening: "📞"
        case .interview: "🤝"
        case .offer: "🎉"
        case .rejected: "❌"
        case .accepted: "✅"
        }
    }

    public var isPositive: Bool {
        self == .offer || self == .accepted
    }

    public var isNegative: Bool {
        self == .rejected
    }
}

public struct Interview: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var company: String
    public var position: String
    public var status: InterviewStatus
    public var appliedDate: Date
    public var note: String

    public init(
        id: String,
        company: String,
        position: String,
        status: InterviewStatus = .applied,
        appliedDate: Date,
        note: String = ""
    ) {
        self.id = id
        self.company = company
        self.position = position
        self.status = status
        self.appliedDate = appliedDate
        self.note = note
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("int", now: now)
    }
}

extension Interview: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "interviews"
}

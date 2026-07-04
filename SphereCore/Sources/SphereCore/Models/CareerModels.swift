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

public struct Achievement: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var description: String
    public var date: Date
    public var impact: String

    public init(
        id: String,
        title: String,
        description: String = "",
        date: Date,
        impact: String = ""
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.date = date
        self.impact = impact
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("achv", now: now)
    }
}

extension Achievement: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "achievements"
}

public struct NetworkContact: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var role: String
    public var company: String
    public var note: String
    public var lastContact: Date?

    public init(
        id: String,
        name: String,
        role: String = "",
        company: String = "",
        note: String = "",
        lastContact: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.company = company
        self.note = note
        self.lastContact = lastContact
    }

    /// Days since the last touch; a large sentinel when never contacted.
    public func daysSinceContact(asOf now: Date = Date()) -> Int {
        guard let lastContact else { return 9_999 }
        return Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: lastContact),
            to: Calendar.current.startOfDay(for: now)
        ).day ?? 0
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("netc", now: now)
    }
}

extension NetworkContact: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "network_contacts"
}

// MARK: - career-v3 (skills, salary, goals, 1:1s, brag doc)

public struct CareerSkill: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var category: String
    /// 1–5 proficiency.
    public var level: Int

    public init(id: String, name: String, category: String = "General", level: Int = 3) {
        self.id = id
        self.name = name
        self.category = category
        self.level = level
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("careerskill", now: now) }
}

extension CareerSkill: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "career_skills"
}

public struct SalaryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var amount: Double
    public var role: String
    public var company: String
    public var date: Date
    public var note: String

    public init(
        id: String, amount: Double, role: String = "", company: String = "",
        date: Date, note: String = ""
    ) {
        self.id = id
        self.amount = amount
        self.role = role
        self.company = company
        self.date = date
        self.note = note
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("salary", now: now) }
}

extension SalaryEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "salary_entries"
}

public enum CareerGoalStatus: String, Codable, CaseIterable, Sendable {
    case active, achieved, paused

    public var label: String {
        switch self {
        case .active: "Active"
        case .achieved: "Achieved"
        case .paused: "Paused"
        }
    }
}

public struct CareerGoal: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var status: CareerGoalStatus
    public var progressPercent: Int
    public var targetDate: Date?
    public var note: String

    public init(
        id: String, title: String, status: CareerGoalStatus = .active,
        progressPercent: Int = 0, targetDate: Date? = nil, note: String = ""
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.progressPercent = progressPercent
        self.targetDate = targetDate
        self.note = note
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("careergoal", now: now) }
}

extension CareerGoal: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "career_goals"
}

/// Notes for a recurring 1:1 with a manager, report, or mentor, with the
/// talking points to raise next time.
public struct OneOnOne: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var person: String
    public var role: String
    public var date: Date
    public var notes: String
    public var talkingPoints: [String]

    public init(
        id: String, person: String, role: String = "", date: Date,
        notes: String = "", talkingPoints: [String] = []
    ) {
        self.id = id
        self.person = person
        self.role = role
        self.date = date
        self.notes = notes
        self.talkingPoints = talkingPoints
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("oneonone", now: now) }
}

extension OneOnOne: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "one_on_ones"
}

/// Builds a review-ready "brag document" from achievements + completed work —
/// the thing everyone wishes they'd kept before a performance review.
public enum BragDocument {
    public static func build(
        achievements: [Achievement], doneTasks: [CareerTask], now: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var lines: [String] = ["# Brag document", "_As of \(formatter.string(from: now))_", ""]

        if !achievements.isEmpty {
            lines.append("## Achievements")
            for achievement in achievements {
                var line = "- **\(achievement.title)**"
                if !achievement.impact.isEmpty { line += " — \(achievement.impact)" }
                lines.append(line)
            }
            lines.append("")
        }

        if !doneTasks.isEmpty {
            lines.append("## Completed work")
            let byProject = Dictionary(grouping: doneTasks) {
                $0.project.isEmpty ? "General" : $0.project
            }
            for project in byProject.keys.sorted() {
                lines.append("### \(project)")
                for task in byProject[project] ?? [] {
                    lines.append("- \(task.title)")
                }
            }
            lines.append("")
        }

        if achievements.isEmpty && doneTasks.isEmpty {
            lines.append("Nothing logged yet — add achievements and complete tasks to fill this in.")
        }

        return lines.joined(separator: "\n")
    }
}

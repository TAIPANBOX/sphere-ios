import Foundation
import GRDB

public enum BookStatus: String, Codable, CaseIterable, Sendable {
    case reading
    case wantToRead
    case completed
}

public struct Book: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var author: String
    public var currentPage: Int
    public var totalPages: Int
    public var status: BookStatus
    public var emoji: String
    public var notes: String
    public var quotes: [String]

    public init(
        id: String,
        title: String,
        author: String = "",
        currentPage: Int = 0,
        totalPages: Int,
        status: BookStatus = .wantToRead,
        emoji: String = "📖",
        notes: String = "",
        quotes: [String] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.status = status
        self.emoji = emoji
        self.notes = notes
        self.quotes = quotes
    }

    public var progress: Double {
        totalPages > 0 ? Double(currentPage) / Double(totalPages) : 0
    }

    public var isCompleted: Bool {
        status == .completed
    }

    public static func newID(now: Date = Date()) -> String {
        "book_\(Int64(now.timeIntervalSince1970 * 1000))"
    }
}

extension Book: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "books"
}

public enum SkillStatus: String, Codable, CaseIterable, Sendable {
    case learning
    case wantToLearn
    case mastered

    public var label: String {
        switch self {
        case .learning: "Learning"
        case .wantToLearn: "Want to learn"
        case .mastered: "Mastered"
        }
    }
}

public struct LearningSkill: Codable, Equatable, Identifiable, Sendable {
    public static let maxLevel = 5

    public var id: String
    public var name: String
    public var category: String
    /// Proficiency 1–5, shown as dots.
    public var level: Int
    public var status: SkillStatus
    public var note: String

    public init(
        id: String,
        name: String,
        category: String = "General",
        level: Int = 1,
        status: SkillStatus = .wantToLearn,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.level = level
        self.status = status
        self.note = note
    }

    public static func newID(now: Date = Date()) -> String {
        "skill_\(Int64(now.timeIntervalSince1970 * 1000))"
    }
}

extension LearningSkill: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "skills"
}

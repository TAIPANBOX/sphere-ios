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
        EntityID.make("book", now: now)
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
        EntityID.make("skill", now: now)
    }
}

extension LearningSkill: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "skills"
}

// MARK: - learning-v2 (courses, languages, flashcards, queue)

public enum CourseStatus: String, Codable, CaseIterable, Sendable {
    case active, completed, paused
}

public struct Course: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var provider: String
    public var progressPercent: Int
    public var status: CourseStatus
    public var note: String

    public init(
        id: String, name: String, provider: String = "",
        progressPercent: Int = 0, status: CourseStatus = .active, note: String = ""
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.progressPercent = progressPercent
        self.status = status
        self.note = note
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("course", now: now) }
}

extension Course: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "courses"
}

public struct LanguageStudy: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// CEFR-ish level label (A1…C2) or free text.
    public var level: String
    public var note: String

    public init(id: String, name: String, level: String = "A1", note: String = "") {
        self.id = id
        self.name = name
        self.level = level
        self.note = note
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("lang", now: now) }
}

extension LanguageStudy: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "languages"
}

public enum QueueKind: String, Codable, CaseIterable, Sendable {
    case article, video, course, podcast, other

    public var emoji: String {
        switch self {
        case .article: "📄"
        case .video: "🎬"
        case .course: "🎓"
        case .podcast: "🎧"
        case .other: "🔖"
        }
    }
}

/// "Read/watch later" queue — one place for everything you mean to consume.
public struct LearningQueueItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var kind: QueueKind
    public var url: String
    public var done: Bool
    public var createdAt: Date

    public init(
        id: String, title: String, kind: QueueKind = .other,
        url: String = "", done: Bool = false, createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.url = url
        self.done = done
        self.createdAt = createdAt
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("queue", now: now) }
}

extension LearningQueueItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "learning_queue"
}

public enum ReviewGrade: String, Codable, Sendable {
    case forgot, good, easy
}

/// A spaced-repetition flashcard. The scheduling (`SpacedRepetition`) spaces
/// reviews to fight the Ebbinghaus forgetting curve — the same exponential
/// decay Engram uses for memories — by extending the interval each time recall
/// succeeds, and resetting it when it fails.
public struct Flashcard: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var deck: String
    public var front: String
    public var back: String
    public var easiness: Double
    public var intervalDays: Int
    public var repetitions: Int
    public var dueDate: Date
    public var lastReviewed: Date?

    public init(
        id: String, deck: String = "General", front: String, back: String,
        easiness: Double = 2.5, intervalDays: Int = 0, repetitions: Int = 0,
        dueDate: Date, lastReviewed: Date? = nil
    ) {
        self.id = id
        self.deck = deck
        self.front = front
        self.back = back
        self.easiness = easiness
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.dueDate = dueDate
        self.lastReviewed = lastReviewed
    }

    public func isDue(asOf now: Date = Date()) -> Bool {
        DayKey.calendar.startOfDay(for: dueDate) <= DayKey.calendar.startOfDay(for: now)
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("card", now: now) }
}

extension Flashcard: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "flashcards"
}

/// SM-2-style scheduler: successful recalls stretch the review interval
/// (memory strength grew, so it can survive longer before dropping below the
/// retention threshold), a lapse resets it. `easiness` adapts per card.
public enum SpacedRepetition {
    public static func schedule(_ card: Flashcard, grade: ReviewGrade, now: Date = Date()) -> Flashcard {
        var ease = card.easiness
        var reps = card.repetitions
        var interval = card.intervalDays

        switch grade {
        case .forgot:
            reps = 0
            interval = 1
            ease = max(ease - 0.2, 1.3)
        case .good:
            reps += 1
            interval = nextInterval(reps: reps, previous: interval, ease: ease)
        case .easy:
            reps += 1
            ease += 0.15
            interval = Int((Double(nextInterval(reps: reps, previous: interval, ease: ease)) * 1.3).rounded())
        }

        let due = DayKey.calendar.date(
            byAdding: .day, value: max(interval, 1),
            to: DayKey.calendar.startOfDay(for: now)
        ) ?? now

        var updated = card
        updated.easiness = ease
        updated.repetitions = reps
        updated.intervalDays = max(interval, 1)
        updated.dueDate = due
        updated.lastReviewed = now
        return updated
    }

    private static func nextInterval(reps: Int, previous: Int, ease: Double) -> Int {
        switch reps {
        case ...1: 1
        case 2: 3
        default: max(Int((Double(previous) * ease).rounded()), previous + 1)
        }
    }
}

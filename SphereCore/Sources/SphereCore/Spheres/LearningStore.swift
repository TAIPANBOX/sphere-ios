import Foundation
import GRDB
import Observation

/// Learning sphere store: books library with reading progress and quotes,
/// plus a skills tracker with 1–5 proficiency levels grouped by category.
/// Follows the golden-template shape (docs/HANDOFF.md).
@MainActor
@Observable
public final class LearningStore {
    public private(set) var books: [Book] = []
    public private(set) var skills: [LearningSkill] = []
    public private(set) var courses: [Course] = []
    public private(set) var languages: [LanguageStudy] = []
    public private(set) var queueItems: [LearningQueueItem] = []
    public private(set) var flashcards: [Flashcard] = []

    private let database: AppDatabase
    private let engram: EngramStore?

    public init(database: AppDatabase, engram: EngramStore? = nil) {
        self.database = database
        self.engram = engram
    }

    public func load() async throws {
        let (books, skills, courses, languages, queue, cards) = try await database.writer.read { db in
            (
                try Book.fetchAll(db),
                try LearningSkill.fetchAll(db),
                try Course.fetchAll(db),
                try LanguageStudy.fetchAll(db),
                try LearningQueueItem.fetchAll(db, sql: "SELECT * FROM learning_queue ORDER BY createdAt DESC"),
                try Flashcard.fetchAll(db)
            )
        }
        self.books = books
        self.skills = skills
        self.courses = courses
        self.languages = languages
        self.queueItems = queue
        self.flashcards = cards
    }

    // MARK: - Books

    public var reading: [Book] {
        books.filter { $0.status == .reading }
    }

    public var queue: [Book] {
        books.filter { $0.status == .wantToRead }
    }

    public var completed: [Book] {
        books.filter { $0.status == .completed }
    }

    public func add(_ book: Book) async throws {
        try await database.writer.write { db in try book.insert(db) }
        books.append(book)
        engram?.note(
            agentId: SphereType.learning.rawValue,
            content: "Started tracking book: \"\(book.title)\"",
            tags: ["log", "learning", "book"]
        )
    }

    public func update(_ book: Book) async throws {
        try await database.writer.write { db in try book.save(db) }
        books = books.map { $0.id == book.id ? book : $0 }
    }

    public func remove(id: String) async throws {
        _ = try await database.writer.write { db in try Book.deleteOne(db, key: id) }
        books.removeAll { $0.id == id }
    }

    public func markComplete(id: String) async throws {
        guard var book = books.first(where: { $0.id == id }) else { return }
        book.status = .completed
        book.currentPage = book.totalPages
        try await update(book)
        engram?.note(
            agentId: SphereType.learning.rawValue,
            content: "Finished reading: \"\(book.title)\"",
            tags: ["log", "learning", "book"],
            salience: 0.75
        )
    }

    /// Sets the current page (clamped); reaching the last page completes the
    /// book, anything else keeps/returns it to reading.
    public func setPage(id: String, page: Int) async throws {
        guard var book = books.first(where: { $0.id == id }) else { return }
        let clamped = min(max(page, 0), book.totalPages)
        book.currentPage = clamped
        book.status = clamped >= book.totalPages ? .completed : .reading
        try await update(book)
    }

    public func saveNotes(id: String, notes: String) async throws {
        guard var book = books.first(where: { $0.id == id }) else { return }
        book.notes = notes
        try await update(book)
    }

    public func addQuote(id: String, quote: String) async throws {
        guard var book = books.first(where: { $0.id == id }) else { return }
        book.quotes.append(quote)
        try await update(book)
    }

    public func removeQuote(id: String, at index: Int) async throws {
        guard var book = books.first(where: { $0.id == id }),
              book.quotes.indices.contains(index)
        else { return }
        book.quotes.remove(at: index)
        try await update(book)
    }

    // MARK: - Skills

    public func addSkill(_ skill: LearningSkill) async throws {
        try await database.writer.write { db in try skill.insert(db) }
        skills.append(skill)
    }

    public func updateSkill(_ skill: LearningSkill) async throws {
        try await database.writer.write { db in try skill.save(db) }
        skills = skills.map { $0.id == skill.id ? skill : $0 }
    }

    public func removeSkill(id: String) async throws {
        _ = try await database.writer.write { db in try LearningSkill.deleteOne(db, key: id) }
        skills.removeAll { $0.id == id }
    }

    public func levelUp(id: String) async throws {
        guard var skill = skills.first(where: { $0.id == id }),
              skill.level < LearningSkill.maxLevel
        else { return }
        skill.level += 1
        try await updateSkill(skill)
    }

    public func levelDown(id: String) async throws {
        guard var skill = skills.first(where: { $0.id == id }), skill.level > 1 else { return }
        skill.level -= 1
        try await updateSkill(skill)
    }

    public var skillCategories: [String] {
        Set(skills.map(\.category)).sorted()
    }

    // MARK: - Courses

    public func addCourse(_ course: Course) async throws {
        try await database.writer.write { db in try course.insert(db) }
        courses.append(course)
    }

    public func updateCourse(_ course: Course) async throws {
        try await database.writer.write { db in try course.save(db) }
        courses = courses.map { $0.id == course.id ? course : $0 }
    }

    public func removeCourse(id: String) async throws {
        _ = try await database.writer.write { db in try Course.deleteOne(db, key: id) }
        courses.removeAll { $0.id == id }
    }

    // MARK: - Languages

    public func addLanguage(_ language: LanguageStudy) async throws {
        try await database.writer.write { db in try language.insert(db) }
        languages.append(language)
    }

    public func removeLanguage(id: String) async throws {
        _ = try await database.writer.write { db in try LanguageStudy.deleteOne(db, key: id) }
        languages.removeAll { $0.id == id }
    }

    // MARK: - Read/watch queue

    public var pendingQueue: [LearningQueueItem] { queueItems.filter { !$0.done } }

    public func addQueueItem(_ item: LearningQueueItem) async throws {
        try await database.writer.write { db in try item.insert(db) }
        queueItems.insert(item, at: 0)
    }

    public func toggleQueueItem(id: String) async throws {
        guard let item = queueItems.first(where: { $0.id == id }) else { return }
        let updated = LearningQueueItem(
            id: item.id, title: item.title, kind: item.kind, url: item.url,
            done: !item.done, createdAt: item.createdAt
        )
        try await database.writer.write { db in try updated.save(db) }
        queueItems = queueItems.map { $0.id == id ? updated : $0 }
    }

    public func removeQueueItem(id: String) async throws {
        _ = try await database.writer.write { db in try LearningQueueItem.deleteOne(db, key: id) }
        queueItems.removeAll { $0.id == id }
    }

    // MARK: - Flashcards (spaced repetition)

    public func addFlashcard(_ card: Flashcard) async throws {
        try await database.writer.write { db in try card.insert(db) }
        flashcards.append(card)
    }

    public func removeFlashcard(id: String) async throws {
        _ = try await database.writer.write { db in try Flashcard.deleteOne(db, key: id) }
        flashcards.removeAll { $0.id == id }
    }

    /// Cards due for review now, soonest-due first.
    public func dueFlashcards(asOf now: Date = Date()) -> [Flashcard] {
        flashcards.filter { $0.isDue(asOf: now) }.sorted { $0.dueDate < $1.dueDate }
    }

    /// Grades a card and reschedules it via the spaced-repetition curve.
    public func reviewFlashcard(id: String, grade: ReviewGrade, now: Date = Date()) async throws {
        guard let card = flashcards.first(where: { $0.id == id }) else { return }
        let updated = SpacedRepetition.schedule(card, grade: grade, now: now)
        try await database.writer.write { db in try updated.save(db) }
        flashcards = flashcards.map { $0.id == id ? updated : $0 }
    }

    // MARK: - Agent tools

    public nonisolated var tools: [SphereTool] {
        [
            SphereTool(
                definition: LLMTool(
                    name: "list_books",
                    description: "List the books the user is reading now (with page progress) "
                        + "and the ones they have completed.",
                    inputSchema: ["type": "object", "properties": [:], "required": []]
                ),
                spheres: [.learning],
                silent: true,
                handler: { [weak self] _ in
                    guard let self else { throw CancellationError() }
                    return await self.booksSnapshotJSON()
                }
            ),
        ]
    }

    private func booksSnapshotJSON() -> String {
        JSONValue.object([
            "reading": .array(reading.map { book in
                .object([
                    "title": .string(book.title),
                    "author": .string(book.author),
                    "page": .number(Double(book.currentPage)),
                    "totalPages": .number(Double(book.totalPages)),
                ])
            }),
            "completed": .array(completed.map { .string($0.title) }),
            "total": .number(Double(books.count)),
        ]).encodedString()
    }
}

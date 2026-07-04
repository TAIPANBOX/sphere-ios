import Foundation
import Testing
@testable import SphereCore

@Suite("SpacedRepetition (SM-2)")
struct SpacedRepetitionTests {
    private let cal = DayKey.calendar
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func card() -> Flashcard {
        Flashcard(id: "c", front: "Q", back: "A", dueDate: date(2026, 7, 4))
    }

    @Test func goodRecallsStretchTheInterval() {
        let now = date(2026, 7, 4)
        let r1 = SpacedRepetition.schedule(card(), grade: .good, now: now)
        #expect(r1.repetitions == 1)
        #expect(r1.intervalDays == 1)

        let r2 = SpacedRepetition.schedule(r1, grade: .good, now: now)
        #expect(r2.intervalDays == 3)

        let r3 = SpacedRepetition.schedule(r2, grade: .good, now: now)
        // 3 * 2.5 ease ≈ 8 days — clearly longer.
        #expect(r3.intervalDays >= 7)
        #expect(cal.startOfDay(for: r3.dueDate) == cal.date(byAdding: .day, value: r3.intervalDays, to: now))
    }

    @Test func lapseResetsAndLowersEase() {
        let now = date(2026, 7, 4)
        var c = card()
        c.repetitions = 4
        c.intervalDays = 20
        c.easiness = 2.5
        let r = SpacedRepetition.schedule(c, grade: .forgot, now: now)
        #expect(r.repetitions == 0)
        #expect(r.intervalDays == 1)
        #expect(r.easiness < 2.5)
        #expect(r.easiness >= 1.3)
    }

    @Test func easyGrowsMoreThanGood() {
        let now = date(2026, 7, 4)
        let good = SpacedRepetition.schedule(
            { var c = card(); c.repetitions = 2; c.intervalDays = 3; return c }(),
            grade: .good, now: now
        )
        let easy = SpacedRepetition.schedule(
            { var c = card(); c.repetitions = 2; c.intervalDays = 3; return c }(),
            grade: .easy, now: now
        )
        #expect(easy.intervalDays > good.intervalDays)
        #expect(easy.easiness > good.easiness)
    }
}

@Suite("Learning extras: courses, languages, queue, flashcards")
@MainActor
struct LearningExtrasTests {
    private func makeStore() throws -> (LearningStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (LearningStore(database: database), database)
    }

    @Test func crudPersistsAcrossReload() async throws {
        let (store, database) = try makeStore()
        try await store.load()
        try await store.addCourse(Course(id: "c", name: "Swift Concurrency", provider: "Apple"))
        try await store.addLanguage(LanguageStudy(id: "l", name: "Spanish", level: "B1"))
        try await store.addQueueItem(LearningQueueItem(id: "q", title: "Great article", kind: .article, createdAt: Date()))

        let reloaded = LearningStore(database: database)
        try await reloaded.load()
        #expect(reloaded.courses.count == 1)
        #expect(reloaded.languages.first?.level == "B1")
        #expect(reloaded.pendingQueue.count == 1)

        try await reloaded.toggleQueueItem(id: "q")
        #expect(reloaded.pendingQueue.isEmpty)
    }

    @Test func flashcardReviewSchedulesAndDueFilter() async throws {
        let (store, _) = try makeStore()
        try await store.load()
        let now = Date()
        try await store.addFlashcard(Flashcard(id: "f", front: "hola", back: "hi", dueDate: now))
        #expect(store.dueFlashcards(asOf: now).count == 1)

        try await store.reviewFlashcard(id: "f", grade: .good, now: now)
        // Now scheduled a day out → not due today.
        #expect(store.dueFlashcards(asOf: now).isEmpty)
        #expect(store.flashcards.first?.repetitions == 1)
    }
}

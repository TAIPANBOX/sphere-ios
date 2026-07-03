import Foundation
import Testing
@testable import SphereCore

@Suite("LearningStore")
@MainActor
struct LearningStoreTests {
    private func makeStore(engram: EngramStore? = nil) throws -> (LearningStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (LearningStore(database: database, engram: engram), database)
    }

    // MARK: - Books

    @Test func booksSplitByStatusAndPersist() async throws {
        let (store, database) = try makeStore()
        try await store.add(Book(id: "b1", title: "Swift in Depth", totalPages: 400, status: .reading))
        try await store.add(Book(id: "b2", title: "Clean Code", totalPages: 300))
        try await store.add(Book(id: "b3", title: "Old Book", totalPages: 100, status: .completed))

        #expect(store.reading.map(\.id) == ["b1"])
        #expect(store.queue.map(\.id) == ["b2"])
        #expect(store.completed.map(\.id) == ["b3"])

        let reloaded = LearningStore(database: database)
        try await reloaded.load()
        #expect(reloaded.books.count == 3)
    }

    @Test func setPageClampsAndDrivesStatus() async throws {
        let (store, _) = try makeStore()
        try await store.add(Book(id: "b1", title: "Book", totalPages: 200))

        try await store.setPage(id: "b1", page: 50)
        #expect(store.books[0].currentPage == 50)
        #expect(store.books[0].status == .reading)

        try await store.setPage(id: "b1", page: 500)
        #expect(store.books[0].currentPage == 200)
        #expect(store.books[0].status == .completed)

        try await store.setPage(id: "b1", page: -5)
        #expect(store.books[0].currentPage == 0)
        #expect(store.books[0].status == .reading)
    }

    @Test func markCompleteFillsPagesAndNotesEngram() async throws {
        let engram = try EngramStore.inMemory()
        let (store, _) = try makeStore(engram: engram)
        try await store.add(Book(id: "b1", title: "Атомні звички", totalPages: 320, status: .reading))
        try await store.markComplete(id: "b1")

        #expect(store.books[0].isCompleted)
        #expect(store.books[0].currentPage == 320)

        var count = 0
        for _ in 0..<50 where count < 2 {
            count = try await engram.count(agentId: "learning")
            if count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        }
        let memories = try await engram.recall("finished reading", agentId: "learning")
        #expect(memories.contains { $0.content == "Finished reading: \"Атомні звички\"" })
    }

    @Test func quotesAndNotesRoundTrip() async throws {
        let (store, database) = try makeStore()
        try await store.add(Book(id: "b1", title: "Book", totalPages: 100))
        try await store.addQuote(id: "b1", quote: "First quote")
        try await store.addQuote(id: "b1", quote: "Second quote")
        try await store.removeQuote(id: "b1", at: 0)
        try await store.saveNotes(id: "b1", notes: "Great chapter 3")

        let reloaded = LearningStore(database: database)
        try await reloaded.load()
        #expect(reloaded.books[0].quotes == ["Second quote"])
        #expect(reloaded.books[0].notes == "Great chapter 3")
    }

    // MARK: - Skills

    @Test func skillLevelsClampBetween1And5() async throws {
        let (store, _) = try makeStore()
        try await store.addSkill(LearningSkill(id: "s1", name: "SwiftUI", level: 4))

        try await store.levelUp(id: "s1")
        try await store.levelUp(id: "s1")
        #expect(store.skills[0].level == 5)

        for _ in 0..<6 {
            try await store.levelDown(id: "s1")
        }
        #expect(store.skills[0].level == 1)
    }

    @Test func skillCategoriesAreSortedUnique() async throws {
        let (store, database) = try makeStore()
        try await store.addSkill(LearningSkill(id: "s1", name: "Swift", category: "Mobile Dev"))
        try await store.addSkill(LearningSkill(id: "s2", name: "GRDB", category: "Mobile Dev"))
        try await store.addSkill(LearningSkill(id: "s3", name: "Piano", category: "Music"))

        #expect(store.skillCategories == ["Mobile Dev", "Music"])

        try await store.removeSkill(id: "s3")
        let reloaded = LearningStore(database: database)
        try await reloaded.load()
        #expect(reloaded.skillCategories == ["Mobile Dev"])
    }

    // MARK: - Agent tools

    @Test func listBooksToolIsSilentAndComplete() async throws {
        let (store, _) = try makeStore()
        try await store.add(Book(
            id: "b1", title: "Swift in Depth", author: "T. in 't Veen",
            currentPage: 120, totalPages: 400, status: .reading
        ))
        try await store.add(Book(id: "b2", title: "Clean Code", totalPages: 300, status: .completed))
        try await store.add(Book(id: "b3", title: "Queued", totalPages: 100))
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(id: "t1", name: "list_books", input: .object([:]))
        let result = await registry.execute(call)
        let json = JSONValue.decoded(from: result.content)

        #expect(json?["reading"]?.arrayValue?.count == 1)
        #expect(json?["reading"]?[0]?["title"]?.stringValue == "Swift in Depth")
        #expect(json?["reading"]?[0]?["page"]?.intValue == 120)
        #expect(json?["completed"]?[0]?.stringValue == "Clean Code")
        #expect(json?["total"]?.intValue == 3)
        #expect(registry.confirmation(for: call) == nil)
    }

    @Test func toolsAreScopedToLearningSphere() throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)
        #expect(registry.toolsFor(.learning).map(\.name) == ["list_books"])
        #expect(registry.toolsFor(.health).isEmpty)
    }
}

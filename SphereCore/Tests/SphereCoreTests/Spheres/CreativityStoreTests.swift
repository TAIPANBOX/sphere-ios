import Foundation
import Testing
@testable import SphereCore

@Suite("CreativityStore")
@MainActor
struct CreativityStoreTests {
    private func makeStore(engram: EngramStore? = nil) throws -> (CreativityStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (CreativityStore(database: database, engram: engram), database)
    }

    // MARK: - Projects

    @Test func projectsGroupByStatusAndPersist() async throws {
        let (store, database) = try makeStore()
        let now = Date()
        try await store.add(CreativeProject(id: "c1", title: "Novel", type: .writing, createdAt: now))
        try await store.add(CreativeProject(
            id: "c2", title: "Song idea", type: .music, status: .idea, createdAt: now
        ))
        try await store.add(CreativeProject(
            id: "c3", title: "Shipped album", type: .music, status: .completed,
            progressPercent: 100, createdAt: now
        ))

        #expect(store.inProgress.map(\.id) == ["c1"])
        #expect(store.ideaBacklog.map(\.id) == ["c2"])
        #expect(store.completed.map(\.id) == ["c3"])

        let reloaded = CreativityStore(database: database)
        try await reloaded.load()
        #expect(reloaded.projects.count == 3)
    }

    @Test func setProgressClampsCompletesAndStampsLastWorkedOn() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        try await store.add(CreativeProject(id: "c1", title: "Film", type: .video, createdAt: now))

        try await store.setProgress(id: "c1", percent: 120, on: now)
        #expect(store.projects[0].progressPercent == 100)
        #expect(store.projects[0].status == .completed)
        #expect(store.projects[0].lastWorkedOn == now)

        try await store.setProgress(id: "c1", percent: 50, on: now)
        #expect(store.projects[0].status == .inProgress)
    }

    @Test func collaboratorsRoundTrip() async throws {
        let (store, database) = try makeStore()
        try await store.add(CreativeProject(id: "c1", title: "Band", type: .music, createdAt: Date()))
        try await store.addCollaborator(id: "c1", name: "Olena")
        try await store.addCollaborator(id: "c1", name: "Max")
        try await store.removeCollaborator(id: "c1", at: 0)

        let reloaded = CreativityStore(database: database)
        try await reloaded.load()
        #expect(reloaded.projects[0].collaborators == ["Max"])
    }

    @Test func addNotesProjectIntoEngram() async throws {
        let engram = try EngramStore.inMemory()
        let (store, _) = try makeStore(engram: engram)
        try await store.add(CreativeProject(id: "c1", title: "Street photo series", type: .photography, createdAt: Date()))

        var count = 0
        for _ in 0..<50 where count == 0 {
            count = try await engram.count(agentId: "creativity")
            if count == 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        let memories = try await engram.recall("project", agentId: "creativity")
        #expect(memories.first?.content == "Started creative project: Street photo series (photography)")
    }

    // MARK: - Ideas

    @Test func ideasSortNewestFirstAndTruncateEngramPreview() async throws {
        let engram = try EngramStore.inMemory()
        let (store, _) = try makeStore(engram: engram)
        let now = Date()
        try await store.addIdea("Old idea", on: now.addingTimeInterval(-60))
        try await store.addIdea(String(repeating: "і", count: 150), tag: "Story", on: now)

        #expect(store.recentIdeas.first?.tag == "Story")

        var count = 0
        for _ in 0..<50 where count < 2 {
            count = try await engram.count(agentId: "creativity")
            if count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        }
        let memories = try await engram.recall("idea", agentId: "creativity")
        let long = memories.first { $0.content.hasPrefix("Captured idea: іі") }
        #expect(long?.content.hasSuffix("…") == true)
    }

    // MARK: - Agent tools

    @Test func captureIdeaToolCreatesAndConfirms() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(
            id: "t1", name: "capture_idea",
            input: ["content": "A song about the sea", "tag": "Melody"]
        )
        let result = await registry.execute(call)
        #expect(!result.isError)
        #expect(store.ideas.first?.content == "A song about the sea")
        #expect(store.ideas.first?.tag == "Melody")
        #expect(registry.confirmation(for: call) == "Captured the idea 💡")

        let bad = await registry.execute(
            LLMToolCall(id: "t2", name: "capture_idea", input: .object([:]))
        )
        #expect(bad.isError)
    }

    @Test func creativitySummaryToolIsSilentAndComplete() async throws {
        let (store, _) = try makeStore()
        try await store.add(CreativeProject(
            id: "c1", title: "Novel", type: .writing, progressPercent: 40, createdAt: Date()
        ))
        try await store.addIdea("Plot twist")
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(id: "t1", name: "get_creativity_summary", input: .object([:]))
        let result = await registry.execute(call)
        let json = JSONValue.decoded(from: result.content)

        #expect(json?["projects"]?[0]?["title"]?.stringValue == "Novel")
        #expect(json?["projects"]?[0]?["progress"]?.intValue == 40)
        #expect(json?["recentIdeas"]?[0]?["content"]?.stringValue == "Plot twist")
        #expect(registry.confirmation(for: call) == nil)
    }

    @Test func toolsAreScopedToCreativitySphere() throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)
        #expect(
            registry.toolsFor(.creativity).map(\.name).sorted()
                == ["capture_idea", "get_creativity_summary"]
        )
        #expect(registry.toolsFor(.home).isEmpty)
    }
}

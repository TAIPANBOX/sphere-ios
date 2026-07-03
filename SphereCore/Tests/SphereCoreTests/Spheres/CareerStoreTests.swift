import Foundation
import Testing
@testable import SphereCore

@Suite("CareerStore")
@MainActor
struct CareerStoreTests {
    private func makeStore(engram: EngramStore? = nil) throws -> (CareerStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (CareerStore(database: database, engram: engram), database)
    }

    private func task(
        _ id: String,
        _ title: String,
        project: String = "",
        status: TaskStatus = .todo,
        due: Date? = nil,
        createdAt: Date = Date()
    ) -> CareerTask {
        CareerTask(id: id, title: title, project: project, status: status, dueDate: due, createdAt: createdAt)
    }

    // MARK: - Tasks

    @Test func addKeepsNewestFirstAndPersists() async throws {
        let (store, database) = try makeStore()
        let now = Date()
        try await store.add(task("t1", "Old", createdAt: now.addingTimeInterval(-60)))
        try await store.add(task("t2", "New", createdAt: now))

        #expect(store.tasks.map(\.id) == ["t2", "t1"])

        let reloaded = CareerStore(database: database)
        try await reloaded.load()
        #expect(reloaded.tasks.map(\.id) == ["t2", "t1"])
    }

    @Test func addNotesIntoEngramWithProject() async throws {
        let engram = try EngramStore.inMemory()
        let (store, _) = try makeStore(engram: engram)
        try await store.add(task("t1", "Ship sync feature", project: "Sphere"))

        var count = 0
        for _ in 0..<50 where count == 0 {
            count = try await engram.count(agentId: "career")
            if count == 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        let memories = try await engram.recall("task", agentId: "career")
        #expect(memories.first?.content == "New career task: Ship sync feature (Sphere)")
    }

    @Test func toggleStatusFlipsDoneAndBack() async throws {
        let (store, _) = try makeStore()
        try await store.add(task("t1", "Task"))

        try await store.toggleStatus(id: "t1")
        #expect(store.tasks[0].status == .done)
        #expect(store.doneCount == 1)
        #expect(store.openTasks.isEmpty)

        try await store.toggleStatus(id: "t1")
        #expect(store.tasks[0].status == .todo)
    }

    @Test func overdueCountsOpenPastDueOnly() async throws {
        let (store, _) = try makeStore()
        let yesterday = Date().addingTimeInterval(-86_400)
        let tomorrow = Date().addingTimeInterval(86_400)
        try await store.add(task("t1", "Late", due: yesterday))
        try await store.add(task("t2", "Late but done", status: .done, due: yesterday))
        try await store.add(task("t3", "Future", due: tomorrow))
        try await store.add(task("t4", "No due"))

        #expect(store.overdueCount() == 1)
    }

    @Test func todayTasksIncludesUnscheduledAndDueToday() async throws {
        let (store, _) = try makeStore()
        try await store.add(task("t1", "Due today", due: Date()))
        try await store.add(task("t2", "Unscheduled"))
        try await store.add(task("t3", "Due tomorrow", due: Date().addingTimeInterval(86_400)))
        try await store.add(task("t4", "Done today", status: .done, due: Date()))

        #expect(Set(store.todayTasks().map(\.id)) == ["t1", "t2"])
    }

    // MARK: - Projects

    @Test func projectsActiveFilterAndDaysRemaining() async throws {
        let (store, database) = try makeStore()
        let inFiveDays = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        try await store.addProject(CareerProject(
            id: "p1", name: "Sphere iOS", role: "Solo dev",
            progressPercent: 40, deadline: inFiveDays
        ))
        try await store.addProject(CareerProject(id: "p2", name: "Paused", status: .onHold))

        #expect(store.activeProjects.map(\.id) == ["p1"])
        #expect(store.projects[0].daysRemaining() == 5)

        var project = store.projects[0]
        project.progressPercent = 75
        try await store.updateProject(project)

        let reloaded = CareerStore(database: database)
        try await reloaded.load()
        #expect(reloaded.projects.first { $0.id == "p1" }?.progressPercent == 75)
    }

    // MARK: - Interviews

    @Test func interviewStatusPipelinePersists() async throws {
        let (store, database) = try makeStore()
        try await store.addInterview(Interview(
            id: "i1", company: "Acme", position: "iOS Engineer", appliedDate: Date()
        ))

        try await store.setInterviewStatus(id: "i1", status: .offer)
        #expect(store.interviews[0].status == .offer)
        #expect(store.interviews[0].status.isPositive)

        let reloaded = CareerStore(database: database)
        try await reloaded.load()
        #expect(reloaded.interviews[0].status == .offer)

        try await store.removeInterview(id: "i1")
        #expect(store.interviews.isEmpty)
    }

    // MARK: - Agent tools

    @Test func addCareerTaskToolCreatesWithDueDate() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(
            id: "t1", name: "add_career_task",
            input: [
                "title": "Prepare demo", "project": "Sphere",
                "priority": "high", "dueDate": "2026-07-10",
            ]
        )
        let result = await registry.execute(call)
        #expect(!result.isError)
        #expect(store.tasks.count == 1)
        #expect(store.tasks[0].priority == .high)
        #expect(store.tasks[0].dueDate.map { DayKey.make($0) } == "2026-07-10")
        #expect(registry.confirmation(for: call) == "Added career task: Prepare demo")
    }

    @Test func addCareerTaskToolToleratesBadInput() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)

        let missingTitle = await registry.execute(
            LLMToolCall(id: "t1", name: "add_career_task", input: .object([:]))
        )
        #expect(missingTitle.isError)

        // Unparseable due date and unknown priority degrade, not fail.
        let odd = await registry.execute(LLMToolCall(
            id: "t2", name: "add_career_task",
            input: ["title": "Task", "dueDate": "next friday", "priority": "asap"]
        ))
        #expect(!odd.isError)
        #expect(store.tasks[0].dueDate == nil)
        #expect(store.tasks[0].priority == .medium)
    }

    @Test func listCareerTasksToolShowsOpenOnly() async throws {
        let (store, _) = try makeStore()
        let yesterday = Date().addingTimeInterval(-86_400)
        try await store.add(task("t1", "Open late", project: "P", due: yesterday))
        try await store.add(task("t2", "Done", status: .done))
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(id: "t1", name: "list_career_tasks", input: .object([:]))
        let result = await registry.execute(call)
        let json = JSONValue.decoded(from: result.content)

        #expect(json?["open"]?.intValue == 1)
        #expect(json?["tasks"]?[0]?["title"]?.stringValue == "Open late")
        #expect(json?["tasks"]?[0]?["overdue"]?.boolValue == true)
        #expect(json?["tasks"]?[0]?["due"]?.stringValue == DayKey.make(yesterday))
        #expect(registry.confirmation(for: call) == nil)
    }

    @Test func toolsAreScopedToCareerSphere() throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)
        #expect(
            registry.toolsFor(.career).map(\.name).sorted()
                == ["add_career_task", "list_career_tasks"]
        )
        #expect(registry.toolsFor(.learning).isEmpty)
    }
}

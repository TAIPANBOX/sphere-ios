import Foundation
import Testing
@testable import SphereCore

@Suite("BragDocument")
struct BragDocumentTests {
    @Test func buildsSectionsFromAchievementsAndDoneTasks() {
        let achievements = [
            Achievement(id: "a", title: "Shipped v2", date: Date(), impact: "+30% signups")
        ]
        let tasks = [
            CareerTask(id: "t1", title: "Design API", project: "Platform", status: .done, createdAt: Date()),
            CareerTask(id: "t2", title: "Write docs", project: "Platform", status: .done, createdAt: Date()),
            CareerTask(id: "t3", title: "Open task", project: "Platform", status: .todo, createdAt: Date()),
        ]
        let doc = BragDocument.build(achievements: achievements, doneTasks: tasks.filter { $0.status == .done })
        #expect(doc.contains("# Brag document"))
        #expect(doc.contains("Shipped v2"))
        #expect(doc.contains("+30% signups"))
        #expect(doc.contains("### Platform"))
        #expect(doc.contains("- Design API"))
        // Open task excluded.
        #expect(!doc.contains("Open task"))
    }

    @Test func emptyStateMessage() {
        let doc = BragDocument.build(achievements: [], doneTasks: [])
        #expect(doc.contains("Nothing logged yet"))
    }
}

@Suite("Career extras: skills, salary, goals, 1:1s")
@MainActor
struct CareerExtrasTests {
    private func makeStore() throws -> (CareerStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (CareerStore(database: database), database)
    }

    @Test func crudPersistsAndSorts() async throws {
        let (store, database) = try makeStore()
        try await store.load()
        try await store.addSkill(CareerSkill(id: "s", name: "Swift", level: 4))
        try await store.addSalary(SalaryEntry(id: "sal1", amount: 90000, date: Date().addingTimeInterval(-86_400)))
        try await store.addSalary(SalaryEntry(id: "sal2", amount: 100000, date: Date()))
        try await store.addCareerGoal(CareerGoal(id: "g", title: "Become staff eng"))
        try await store.addOneOnOne(OneOnOne(id: "o", person: "Anna", role: "Manager", date: Date(), talkingPoints: ["Raise"]))

        // Salary newest first.
        #expect(store.latestSalary?.amount == 100000)

        let reloaded = CareerStore(database: database)
        try await reloaded.load()
        #expect(reloaded.careerSkills.count == 1)
        #expect(reloaded.salaryHistory.count == 2)
        #expect(reloaded.careerGoals.first?.title == "Become staff eng")
        #expect(reloaded.oneOnOnes.first?.talkingPoints == ["Raise"])
    }

    @Test func bragDocumentReadsFromStore() async throws {
        let (store, _) = try makeStore()
        try await store.load()
        try await store.add(CareerTask(id: "t", title: "Launch feature", createdAt: Date()))
        try await store.toggleStatus(id: "t") // mark done (or a completion path)
        let doc = store.bragDocument()
        #expect(doc.contains("Brag document"))
    }
}

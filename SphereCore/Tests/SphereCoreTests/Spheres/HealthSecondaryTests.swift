import Foundation
import Testing
@testable import SphereCore

@Suite("Medication model")
struct MedicationModelTests {
    @Test func takenTodayAndToggleAreIdempotent() {
        let now = Date()
        var med = Medication(id: "m1", name: "Vitamin D")
        #expect(!med.takenToday(on: now))

        med = med.markingTaken(on: now)
        #expect(med.takenToday(on: now))
        // Marking again doesn't duplicate.
        #expect(med.markingTaken(on: now).takenDates.count == 1)

        med = med.unmarkingTaken(on: now)
        #expect(!med.takenToday(on: now))
    }
}

@Suite("HealthStore medications & labs")
@MainActor
struct HealthSecondaryTests {
    private func makeStore(engram: EngramStore? = nil) throws -> (HealthStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (HealthStore(database: database, engram: engram), database)
    }

    @Test func medicationsPersistAndToggle() async throws {
        let engram = try EngramStore.inMemory()
        let (store, database) = try makeStore(engram: engram)
        try await store.load()
        try await store.addMedication(Medication(
            id: "m1", name: "Levothyroxine", dosage: "50 mcg", frequency: .once
        ))
        try await store.addMedication(Medication(id: "m2", name: "Vitamin D"))

        try await store.toggleMedication(id: "m1")
        #expect(store.medicationsTakenToday() == 1)
        try await store.toggleMedication(id: "m1")
        #expect(store.medicationsTakenToday() == 0)

        try await store.toggleMedication(id: "m2")
        let reloaded = HealthStore(database: database)
        try await reloaded.load()
        #expect(reloaded.medications.count == 2)
        #expect(reloaded.medicationsTakenToday() == 1)

        var count = 0
        for _ in 0..<50 where count < 2 {
            count = try await engram.count(agentId: "health")
            if count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        }
        let memories = try await engram.recall("medication", agentId: "health")
        #expect(memories.contains { $0.content == "Started medication: Levothyroxine (50 mcg)" })
    }

    @Test func removingMedicationDropsIt() async throws {
        let (store, _) = try makeStore()
        try await store.addMedication(Medication(id: "m1", name: "Aspirin"))
        try await store.removeMedication(id: "m1")
        #expect(store.medications.isEmpty)
    }

    @Test func labResultsPersistNewestFirst() async throws {
        let (store, database) = try makeStore()
        let now = Date()
        try await store.addLabResult(LabResult(
            id: "l1", name: "Cholesterol", value: "190", unit: "mg/dL",
            refRange: "< 200", date: now.addingTimeInterval(-86_400)
        ))
        try await store.addLabResult(LabResult(
            id: "l2", name: "Glucose", value: "140", unit: "mg/dL",
            refRange: "70–99", date: now, isNormal: false
        ))

        // insert(at: 0) keeps newest first in memory.
        #expect(store.labResults.map(\.id) == ["l2", "l1"])

        let reloaded = HealthStore(database: database)
        try await reloaded.load()
        // Reload orders by date DESC.
        #expect(reloaded.labResults.map(\.id) == ["l2", "l1"])
        #expect(reloaded.labResults.first?.isNormal == false)

        try await store.removeLabResult(id: "l2")
        #expect(store.labResults.map(\.id) == ["l1"])
    }

    @Test func healthSnapshotToolIncludesMedications() async throws {
        let (store, _) = try makeStore()
        try await store.load()
        try await store.addMedication(Medication(id: "m1", name: "Levothyroxine"))
        try await store.toggleMedication(id: "m1")
        let registry = SphereToolRegistry(tools: store.tools)

        let result = await registry.execute(
            LLMToolCall(id: "t1", name: "get_health_today", input: .object([:]))
        )
        let json = JSONValue.decoded(from: result.content)
        #expect(json?["medications"]?["total"]?.intValue == 1)
        #expect(json?["medications"]?["takenToday"]?.intValue == 1)
        #expect(json?["medications"]?["names"]?[0]?.stringValue == "Levothyroxine")
    }
}

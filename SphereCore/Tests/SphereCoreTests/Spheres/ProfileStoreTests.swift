import Foundation
import Testing
@testable import SphereCore

@Suite("UserProfile")
struct UserProfileTests {
    @Test func ageComputesFromBirthDate() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 4))!
        let born = calendar.date(from: DateComponents(year: 1994, month: 3, day: 8))!
        var profile = UserProfile(birthDate: born)
        #expect(profile.age(asOf: now) == 32)

        // Birthday later this year → not yet turned.
        profile.birthDate = calendar.date(from: DateComponents(year: 1994, month: 12, day: 1))!
        #expect(profile.age(asOf: now) == 31)

        profile.birthDate = nil
        #expect(profile.age(asOf: now) == nil)
    }

    @Test func agentContextOmitsEmptyFields() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 4))!
        let minimal = UserProfile(name: "Yuko")
        #expect(minimal.agentContext(asOf: now) == "User name: Yuko")

        let rich = UserProfile(
            name: "Yuko",
            birthDate: Calendar.current.date(from: DateComponents(year: 1994, month: 1, day: 1)),
            gender: .male,
            heightCm: 182,
            bloodType: .oPos,
            dietaryRestrictions: ["vegan"],
            foodAllergies: ["nuts", "eggs"],
            healthConditions: ["hypertension"]
        )
        let context = rich.agentContext(asOf: now)
        #expect(context.contains("User name: Yuko"))
        #expect(context.contains("Age: 32"))
        #expect(context.contains("Height: 182 cm"))
        #expect(context.contains("Dietary: vegan"))
        #expect(context.contains("Allergies: nuts, eggs"))
        #expect(context.contains("Health conditions: hypertension"))
        #expect(context.contains("Blood type: O+"))
    }

    @Test func fullNameAndInitialsFallBack() {
        #expect(UserProfile().fullName == "User")
        #expect(UserProfile().initials == "U")
        #expect(UserProfile(name: "Yuko", lastName: "Sem").fullName == "Yuko Sem")
        #expect(UserProfile(name: "Yuko", lastName: "Sem").initials == "YS")
    }

    @Test func isSphereActiveTreatsEmptyAsAll() {
        var profile = UserProfile()
        #expect(profile.isSphereActive(.health))
        profile.activeSpheres = ["health", "finance"]
        #expect(profile.isSphereActive(.health))
        #expect(!profile.isSphereActive(.travel))
    }
}

@Suite("ProfileStore")
@MainActor
struct ProfileStoreTests {
    private func makeStore() throws -> (ProfileStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (ProfileStore(database: database), database)
    }

    @Test func profileRoundTripsThroughDatabase() async throws {
        let (store, database) = try makeStore()
        try await store.save(UserProfile(
            name: "Yuko",
            dietaryRestrictions: ["vegan"],
            foodAllergies: ["nuts"],
            onboarded: true
        ))

        let reloaded = ProfileStore(database: database)
        try await reloaded.load()
        #expect(reloaded.profile.name == "Yuko")
        #expect(reloaded.profile.dietaryRestrictions == ["vegan"])
        #expect(reloaded.profile.onboarded)
        #expect(reloaded.agentContext.contains("Dietary: vegan"))
    }

    @Test func updateMutatesInPlace() async throws {
        let (store, _) = try makeStore()
        try await store.update { $0.name = "Max" }
        try await store.update { $0.heightCm = 178 }
        #expect(store.profile.name == "Max")
        #expect(store.profile.heightCm == 178)
    }

    @Test func sphereTogglingMaterializesFullSetOnFirstDisable() async throws {
        let (store, _) = try makeStore()
        // Empty = all active; disabling one materializes the other 11.
        try await store.setSphereActive(.travel, active: false)
        #expect(store.profile.activeSpheres.count == 11)
        #expect(!store.profile.isSphereActive(.travel))
        #expect(store.profile.isSphereActive(.health))

        // Re-enabling everything collapses back to the empty "all" sentinel.
        try await store.setSphereActive(.travel, active: true)
        #expect(store.profile.activeSpheres.isEmpty)
    }
}

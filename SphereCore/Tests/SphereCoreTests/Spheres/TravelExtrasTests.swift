import Foundation
import Testing
@testable import SphereCore

@Suite("JetLagPlan + CountryGuide")
struct JetLagTests {
    @Test func eastShiftsEarlierCappedAtDifference() {
        let plan = JetLagPlan.plan(hoursDifference: 6, daysBefore: 3)
        #expect(plan.count == 3)
        #expect(plan[0].daysBefore == 3)
        #expect(plan[0].advice.contains("1h earlier"))
        #expect(plan[2].daysBefore == 1)
        #expect(plan[2].advice.contains("3h earlier"))
    }

    @Test func smallDifferenceCapsShift() {
        // Only 2h difference over 3 days → last two days both capped at 2h.
        let plan = JetLagPlan.plan(hoursDifference: 2, daysBefore: 3)
        #expect(plan[2].advice.contains("2h earlier"))
    }

    @Test func westShiftsLaterAndZeroIsEmpty() {
        #expect(JetLagPlan.plan(hoursDifference: -3)[0].advice.contains("later"))
        #expect(JetLagPlan.plan(hoursDifference: 0).isEmpty)
    }

    @Test func countryGuideLookupIsCaseInsensitive() {
        #expect(CountryGuide.info(for: "Japan")?.emergency.contains("110") == true)
        #expect(CountryGuide.info(for: "  ukraine ")?.emergency == "112")
        #expect(CountryGuide.info(for: "Atlantis") == nil)
    }
}

@Suite("Travel extras: journal, budget")
@MainActor
struct TravelExtrasTests {
    @Test func journalAndSpentPersist() async throws {
        let database = try AppDatabase.inMemory()
        let store = TravelStore(database: database)
        try await store.load()
        try await store.add(TravelPlan(id: "t", destination: "Kyoto", country: "Japan", budget: 2000))
        try await store.addJournalEntry(tripId: "t", text: "  Arrived, ate ramen  ")
        try await store.addJournalEntry(tripId: "t", text: "")  // ignored
        try await store.setSpent(planId: "t", amount: 850)

        #expect(store.journal(for: "t").count == 1)
        #expect(store.journal(for: "t").first?.text == "Arrived, ate ramen")

        let reloaded = TravelStore(database: database)
        try await reloaded.load()
        #expect(reloaded.plans.first?.spent == 850)
        #expect(reloaded.journal.count == 1)
    }
}

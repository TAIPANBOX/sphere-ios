import Foundation
import Testing
@testable import SphereCore

@Suite("RitualTiming")
struct RitualTimingTests {
    private let cal = DayKey.calendar
    private func at(_ hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 7, day: 4, hour: hour))!
    }
    private var fresh: DailyRitual { .empty(for: at(9)) }

    @Test func morningWindowWhenNotDone() {
        #expect(RitualTiming.phase(ritual: fresh, asOf: at(8)) == .morning)
    }

    @Test func middayHidesOnceMorningDone() {
        var r = fresh
        r.morningCompletedAt = at(8)
        #expect(RitualTiming.phase(ritual: r, asOf: at(13)) == .none)
    }

    @Test func eveningWindowWhenNotDone() {
        var r = fresh
        r.morningCompletedAt = at(8)
        #expect(RitualTiming.phase(ritual: r, asOf: at(20)) == .evening)
    }

    @Test func eveningHiddenOnceDone() {
        var r = fresh
        r.morningCompletedAt = at(8)
        r.eveningCompletedAt = at(21)
        #expect(RitualTiming.phase(ritual: r, asOf: at(22)) == .none)
    }

    @Test func skippedMorningShowsEveningAtNight() {
        // Never planned in the morning; at night it's the evening prompt.
        #expect(RitualTiming.phase(ritual: fresh, asOf: at(21)) == .evening)
    }

    @Test func preDawnShowsNothing() {
        #expect(RitualTiming.phase(ritual: fresh, asOf: at(3)) == .none)
    }
}

@Suite("RitualStore")
@MainActor
struct RitualStoreTests {
    @Test func morningAndEveningPersist() async throws {
        let database = try AppDatabase.inMemory()
        let store = RitualStore(database: database)
        try await store.load()

        try await store.completeMorning(intention: "  ship the ritual  ", focusIds: ["a", "b"])
        #expect(store.today.morningDone)
        #expect(store.today.intention == "ship the ritual")
        #expect(store.today.plannedFocusIds == ["a", "b"])

        try await store.completeEvening(reflection: "good day")
        #expect(store.today.eveningDone)

        let reloaded = RitualStore(database: database)
        try await reloaded.load()
        #expect(reloaded.today.morningDone)
        #expect(reloaded.today.eveningDone)
        #expect(reloaded.today.reflection == "good day")
    }
}

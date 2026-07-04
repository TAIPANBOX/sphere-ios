import Foundation
import Testing
@testable import SphereCore

@Suite("CyclePredictor")
struct CyclePredictorTests {
    private let cal = DayKey.calendar

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func entry(_ start: Date, end: Date? = nil, flow: FlowLevel = .medium) -> CycleEntry {
        CycleEntry(id: "\(start.timeIntervalSince1970)", startDate: start, endDate: end, flow: flow)
    }

    @Test func emptyHistoryHasNoPrediction() {
        #expect(CyclePredictor.predict([]) == nil)
    }

    @Test func singleEntryUsesDefaultCycleAndIsEstimate() {
        let start = date(2026, 6, 1)
        let p = try! #require(CyclePredictor.predict([entry(start)], asOf: date(2026, 6, 5)))
        #expect(p.isEstimate)
        #expect(p.averageCycleLength == CyclePredictor.defaultCycleLength)
        #expect(p.currentCycleDay == 5)
        // Next period = start + 28 = Jun 29.
        #expect(cal.startOfDay(for: p.nextPeriodStart) == date(2026, 6, 29))
    }

    @Test func averageCycleLengthFromGaps() {
        // Starts 30 days apart → average 30, not the default 28.
        let entries = [
            entry(date(2026, 3, 1)),
            entry(date(2026, 3, 31)),
            entry(date(2026, 4, 30)),
        ]
        #expect(CyclePredictor.averageCycleLength(entries) == 30)
        let p = try! #require(CyclePredictor.predict(entries, asOf: date(2026, 5, 2)))
        #expect(!p.isEstimate)
        #expect(p.averageCycleLength == 30)
        // Cycle day: 2 days after Apr 30 → day 3.
        #expect(p.currentCycleDay == 3)
    }

    @Test func cycleLengthClampsOutOfRangeGaps() {
        // A 90-day gap (missed logging) is clamped to the plausible ceiling.
        let entries = [entry(date(2026, 1, 1)), entry(date(2026, 4, 1))]
        #expect(CyclePredictor.averageCycleLength(entries) == 45)
    }

    @Test func averagePeriodLengthFromCompletedEntries() {
        let entries = [
            entry(date(2026, 3, 1), end: date(2026, 3, 5)), // 5 days
            entry(date(2026, 3, 31), end: date(2026, 4, 3)), // 4 days
        ]
        #expect(CyclePredictor.averagePeriodLength(entries) == 5) // (5+4)/2 = 4.5 → 5
    }

    @Test func phaseIsMenstrualDuringOpenPeriod() {
        let entries = [entry(date(2026, 6, 1)), entry(date(2026, 6, 29))]
        // Two days into the latest period (no end date) → menstrual.
        let p = try! #require(CyclePredictor.predict(entries, asOf: date(2026, 6, 30)))
        #expect(p.isOnPeriod)
        #expect(p.phase == .menstrual)
    }

    @Test func phaseProgressesFollicularOvulationLuteal() {
        // Regular 28-day cycles; last start Jun 1. Next = Jun 29,
        // ovulation = Jun 15, fertile window Jun 10–16.
        let entries = [entry(date(2026, 5, 4)), entry(date(2026, 6, 1))]

        let follicular = try! #require(CyclePredictor.predict(entries, asOf: date(2026, 6, 8)))
        #expect(follicular.phase == .follicular)

        let ovulation = try! #require(CyclePredictor.predict(entries, asOf: date(2026, 6, 15)))
        #expect(ovulation.phase == .ovulation)

        let luteal = try! #require(CyclePredictor.predict(entries, asOf: date(2026, 6, 24)))
        #expect(luteal.phase == .luteal)
    }

    @Test func lateNextPeriodReportsNegativeCountdown() {
        let entries = [entry(date(2026, 5, 4)), entry(date(2026, 6, 1))]
        // Jul 2 is past the predicted Jun 29 start.
        let p = try! #require(CyclePredictor.predict(entries, asOf: date(2026, 7, 2)))
        #expect(p.daysUntilNextPeriod < 0)
    }
}

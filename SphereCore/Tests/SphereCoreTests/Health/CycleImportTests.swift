import Foundation
import Testing
@testable import SphereCore

@Suite("CycleImport")
struct CycleImportTests {
    private let cal = Calendar(identifier: .gregorian)
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    @Test func groupsConsecutiveDaysIntoOnePeriod() {
        let days = [
            CycleFlowDay(date: day(2026, 6, 1), flow: .light),
            CycleFlowDay(date: day(2026, 6, 2), flow: .heavy),
            CycleFlowDay(date: day(2026, 6, 3), flow: .medium),
        ]
        let periods = CycleImport.periods(from: days)
        #expect(periods.count == 1)
        #expect(DayKey.make(periods[0].start) == "2026-06-01")
        #expect(DayKey.make(periods[0].end) == "2026-06-03")
        // Heaviest flow across the period wins.
        #expect(periods[0].flow == .heavy)
    }

    @Test func gapStartsNewPeriod() {
        let days = [
            CycleFlowDay(date: day(2026, 6, 1), flow: .medium),
            CycleFlowDay(date: day(2026, 6, 2), flow: .light),
            CycleFlowDay(date: day(2026, 6, 28), flow: .medium),
            CycleFlowDay(date: day(2026, 6, 29), flow: .light),
        ]
        let periods = CycleImport.periods(from: days)
        #expect(periods.count == 2)
        #expect(DayKey.make(periods[0].start) == "2026-06-01")
        #expect(DayKey.make(periods[1].start) == "2026-06-28")
    }

    @Test func singleDayPeriodStartEqualsEnd() {
        let periods = CycleImport.periods(from: [CycleFlowDay(date: day(2026, 6, 5), flow: .light)])
        #expect(periods.count == 1)
        #expect(periods[0].start == periods[0].end)
    }

    @Test func unsortedInputIsHandled() {
        let days = [
            CycleFlowDay(date: day(2026, 6, 3), flow: .light),
            CycleFlowDay(date: day(2026, 6, 1), flow: .medium),
            CycleFlowDay(date: day(2026, 6, 2), flow: .light),
        ]
        let periods = CycleImport.periods(from: days)
        #expect(periods.count == 1)
        #expect(DayKey.make(periods[0].start) == "2026-06-01")
    }

    @Test func emptyInput() {
        #expect(CycleImport.periods(from: []).isEmpty)
    }
}

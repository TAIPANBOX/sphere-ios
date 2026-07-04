import Foundation
import Testing
@testable import SphereCore

@Suite("SleepImport")
struct SleepImportTests {
    private let cal = Calendar(identifier: .gregorian)

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func sumsAsleepSegmentsIntoOneNightByWakeDay() {
        // Fell asleep 23:00 Jun 7, woke 07:00 Jun 8 → attributed to Jun 8, 8h.
        let intervals = [
            SleepInterval(start: at(2026, 6, 7, 23), end: at(2026, 6, 8, 3), asleep: true),
            SleepInterval(start: at(2026, 6, 8, 3), end: at(2026, 6, 8, 7), asleep: true),
        ]
        let nights = SleepImport.nights(from: intervals)
        #expect(nights.count == 1)
        #expect(DayKey.make(nights[0].date) == "2026-06-08")
        #expect(nights[0].hours == 8)
    }

    @Test func ignoresAwakeInBedSegments() {
        let intervals = [
            SleepInterval(start: at(2026, 6, 7, 23), end: at(2026, 6, 8, 6), asleep: true),
            SleepInterval(start: at(2026, 6, 8, 6), end: at(2026, 6, 8, 7), asleep: false),
        ]
        let nights = SleepImport.nights(from: intervals)
        #expect(nights[0].hours == 7)
    }

    @Test func separatesDistinctNightsSorted() {
        let intervals = [
            SleepInterval(start: at(2026, 6, 8, 0), end: at(2026, 6, 8, 6), asleep: true),
            SleepInterval(start: at(2026, 6, 6, 23), end: at(2026, 6, 7, 6), asleep: true),
        ]
        let nights = SleepImport.nights(from: intervals)
        #expect(nights.count == 2)
        #expect(DayKey.make(nights[0].date) == "2026-06-07")  // earlier night first
        #expect(DayKey.make(nights[1].date) == "2026-06-08")
    }

    @Test func emptyForNoAsleepData() {
        #expect(SleepImport.nights(from: []).isEmpty)
        let awakeOnly = [SleepInterval(start: at(2026, 6, 8, 1), end: at(2026, 6, 8, 2), asleep: false)]
        #expect(SleepImport.nights(from: awakeOnly).isEmpty)
    }
}

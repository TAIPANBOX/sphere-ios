import Foundation
import Testing
@testable import SphereCore

@Suite("CalendarContext")
struct CalendarContextTests {
    private let cal = Calendar(identifier: .gregorian)
    private func at(_ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 7, day: 4, hour: h, minute: m))!
    }
    private var noon: Date { at(12) }

    private func event(_ id: String, _ title: String, _ start: Date, _ end: Date,
                       allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, title: title, start: start, end: end, isAllDay: allDay)
    }

    @Test func filtersToTodayAndSortsAllDayFirst() {
        let tomorrow = cal.date(from: DateComponents(year: 2026, month: 7, day: 5, hour: 9))!
        let events = [
            event("1", "Standup", at(9), at(9, 30)),
            event("2", "Holiday", at(0), at(23, 59), allDay: true),
            event("3", "Tomorrow", tomorrow, tomorrow.addingTimeInterval(3600)),
            event("4", "Lunch", at(13), at(14)),
        ]
        let today = CalendarContext.today(events, now: noon, calendar: cal)
        #expect(today.map(\.id) == ["2", "1", "4"])  // all-day first, then by start
    }

    @Test func timeLabelFormatsOrAllDay() {
        #expect(CalendarContext.timeLabel(event("1", "x", at(9, 5), at(10)), calendar: cal) == "09:05")
        #expect(CalendarContext.timeLabel(event("2", "x", at(0), at(23), allDay: true)) == "All day")
    }

    @Test func summaryListsCountAndTimes() {
        let events = [
            event("1", "Standup", at(9), at(9, 30)),
            event("2", "Dentist", at(16), at(17)),
        ]
        let summary = CalendarContext.summary(events, now: noon)
        #expect(summary.hasPrefix("2 events today:"))
        #expect(summary.contains("09:00 Standup"))
        #expect(summary.contains("16:00 Dentist"))
    }

    @Test func summaryEmptyWhenNothingToday() {
        #expect(CalendarContext.summary([], now: noon).isEmpty)
    }

    @Test func summarySingularForOneEvent() {
        let summary = CalendarContext.summary([event("1", "Call", at(10), at(11))], now: noon)
        #expect(summary.hasPrefix("1 event today:"))
    }
}

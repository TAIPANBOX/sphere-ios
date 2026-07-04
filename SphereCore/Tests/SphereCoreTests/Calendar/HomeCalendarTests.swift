import Foundation
import Testing
@testable import SphereCore

private actor FakeCalendarProvider: CalendarProviding {
    let all: [CalendarEvent]
    let grant: Bool
    init(all: [CalendarEvent], grant: Bool = true) { self.all = all; self.grant = grant }
    func requestAccess() async -> Bool { grant }
    func events(from start: Date, to end: Date) async -> [CalendarEvent] {
        all.filter { $0.start < end && $0.end > start }
    }
}

@Suite("HomeStore calendar")
@MainActor
struct HomeCalendarTests {
    private let cal = Calendar(identifier: .gregorian)
    private func at(_ h: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 7, day: 4, hour: h))!
    }

    private func makeHome(_ provider: FakeCalendarProvider?) throws -> HomeStore {
        let database = try AppDatabase.inMemory()
        return HomeStore(
            health: HealthStore(database: database),
            learning: LearningStore(database: database),
            career: CareerStore(database: database),
            finance: FinanceStore(database: database),
            goals: GoalsStore(database: database),
            calendarProvider: provider
        )
    }

    @Test func refreshPopulatesTodayEvents() async throws {
        let provider = FakeCalendarProvider(all: [
            CalendarEvent(id: "1", title: "Standup", start: at(9), end: at(10)),
        ])
        let home = try makeHome(provider)
        await home.refreshCalendar(now: at(12))
        #expect(home.todayEvents.count == 1)
        #expect(home.todayEvents.first?.title == "Standup")
    }

    @Test func deniedAccessLeavesEventsEmpty() async throws {
        let provider = FakeCalendarProvider(
            all: [CalendarEvent(id: "1", title: "x", start: at(9), end: at(10))], grant: false
        )
        let home = try makeHome(provider)
        await home.refreshCalendar(now: at(12))
        #expect(home.todayEvents.isEmpty)
    }

    @Test func noProviderIsHarmless() async throws {
        let home = try makeHome(nil)
        #expect(home.hasCalendarProvider == false)
        await home.refreshCalendar(now: at(12))
        #expect(home.todayEvents.isEmpty)
    }
}

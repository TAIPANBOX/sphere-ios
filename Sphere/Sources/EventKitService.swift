#if canImport(EventKit)
import EventKit
import Foundation
import SphereCore

/// Live calendar reader backing Home's agenda card and the morning brief.
/// Read-only; requests full access (iOS 17+).
///
/// `@unchecked Sendable`: `EKEventStore` is thread-safe and the class holds no
/// other mutable state.
final class EventKitService: CalendarProviding, @unchecked Sendable {
    private let store = EKEventStore()

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    func events(from start: Date, to end: Date) async -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            CalendarEvent(
                id: event.eventIdentifier
                    ?? "\(event.startDate.timeIntervalSince1970)-\(event.endDate.timeIntervalSince1970)-\(event.title ?? "")",
                title: event.title ?? "(No title)",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                location: event.location
            )
        }
    }
}
#endif

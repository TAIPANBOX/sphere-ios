#if canImport(EventKit)
import EventKit
import Foundation
import SphereCore

/// Live calendar and reminders reader backing Home's agenda card, the
/// morning brief, and the Career reminders import. Read-only; requests full
/// access separately for each (iOS 17+ gates calendar and reminders behind
/// distinct permissions).
///
/// `@unchecked Sendable`: `EKEventStore` is thread-safe and the class holds no
/// other mutable state.
final class EventKitService: CalendarProviding, RemindersProviding, @unchecked Sendable {
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

    // MARK: - Reminders (RemindersProviding)

    func requestRemindersAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    func fetchIncompleteReminders() async -> [ImportedReminder] {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        // Map to the Sendable `ImportedReminder` inside the completion handler
        // itself — `EKReminder` is not Sendable, so it must not cross the
        // continuation boundary.
        return await withCheckedContinuation { (continuation: CheckedContinuation<[ImportedReminder], Never>) in
            store.fetchReminders(matching: predicate) { fetched in
                let imported = (fetched ?? []).map { reminder in
                    ImportedReminder(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "(No title)",
                        dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                        notes: reminder.notes
                    )
                }
                continuation.resume(returning: imported)
            }
        }
    }
}
#endif

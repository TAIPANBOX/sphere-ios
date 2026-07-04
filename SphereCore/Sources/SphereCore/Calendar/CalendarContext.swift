import Foundation

/// One calendar event, flattened so SphereCore stays free of EventKit and the
/// formatting is testable.
public struct CalendarEvent: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?

    public init(
        id: String, title: String, start: Date, end: Date,
        isAllDay: Bool = false, location: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
    }
}

/// Reads the device calendar. Behind a protocol so SphereCore avoids EventKit
/// and the wiring stays testable.
public protocol CalendarProviding: Sendable {
    func requestAccess() async -> Bool
    func events(from start: Date, to end: Date) async -> [CalendarEvent]
}

/// Pure filtering and formatting of calendar events for Home's agenda card and
/// the morning brief.
public enum CalendarContext {
    /// Events touching the calendar day of `now`, all-day first then by start.
    public static func today(
        _ events: [CalendarEvent], now: Date = Date(), calendar: Calendar = .current
    ) -> [CalendarEvent] {
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = dayStart.addingTimeInterval(86_400)
        return events
            .filter { $0.start < dayEnd && $0.end > dayStart }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.start < rhs.start
            }
    }

    /// `HH:mm` start time, or "All day".
    public static func timeLabel(_ event: CalendarEvent, calendar: Calendar = .current) -> String {
        guard !event.isAllDay else { return "All day" }
        let c = calendar.dateComponents([.hour, .minute], from: event.start)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// One-line agenda for the agent's morning brief, or "" when nothing's on.
    public static func summary(_ events: [CalendarEvent], now: Date = Date()) -> String {
        let todays = today(events, now: now)
        guard !todays.isEmpty else { return "" }
        let parts = todays.prefix(6).map { event -> String in
            event.isAllDay ? event.title : "\(timeLabel(event)) \(event.title)"
        }
        let count = todays.count
        return "\(count) event\(count == 1 ? "" : "s") today: " + parts.joined(separator: ", ")
    }
}

import Foundation

/// Notification kinds the app can schedule. `defaultOn` is used when the
/// user has no explicit preference stored (`UserProfile.notificationPrefs`).
/// Only birthdays default on, matching today's behavior.
public enum NotificationCategory: String, CaseIterable, Sendable {
    case birthday, water, medication, bedtime, plant, subscription, morningBrief, nudge, habit

    public var defaultOn: Bool { self == .birthday }

    public var label: String {
        switch self {
        case .birthday: "Birthdays"
        case .water: "Water reminders"
        case .medication: "Medication times"
        case .bedtime: "Bedtime wind-down"
        case .plant: "Plant watering"
        case .subscription: "Subscription renewals"
        case .morningBrief: "Morning brief"
        case .nudge: "Proactive nudges"
        case .habit: "Habit reminders"
        }
    }

    /// Identifier namespace so a sync of one category never disturbs another.
    public var idPrefix: String { "\(rawValue)_" }
}

/// A platform-agnostic description of one scheduled local notification. The
/// app target maps this to `UNCalendarNotificationTrigger`; SphereCore stays
/// free of UserNotifications so the builders are pure and unit-testable.
public struct NotificationPlan: Sendable, Equatable, Identifiable {
    public let id: String
    public let category: NotificationCategory
    public let title: String
    public let body: String
    public let dateComponents: DateComponents
    public let repeats: Bool

    public init(
        id: String,
        category: NotificationCategory,
        title: String,
        body: String,
        dateComponents: DateComponents,
        repeats: Bool
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.body = body
        self.dateComponents = dateComponents
        self.repeats = repeats
    }
}

/// Pure builders turning sphere data into notification plans. Each returns a
/// deterministic, deduplicated list so the engine can diff idempotently.
public enum NotificationPlanBuilder {
    private static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// Yearly reminder at `hour:00` on each contact's birthday.
    public static func birthdays(_ contacts: [Contact], hour: Int = 9) -> [NotificationPlan] {
        let calendar = gregorian
        return contacts.compactMap { contact in
            guard let birthday = contact.birthday else { return nil }
            var parts = calendar.dateComponents([.month, .day], from: birthday)
            parts.hour = hour
            parts.minute = 0
            return NotificationPlan(
                id: NotificationCategory.birthday.idPrefix + contact.id,
                category: .birthday,
                title: "\(contact.name)'s birthday is today 🎂",
                body: "Send some love — your Relationships agent has gift ideas.",
                dateComponents: parts,
                repeats: true
            )
        }
    }

    /// Weekly reminders for each habit on its chosen weekdays at `hour:00`.
    public static func habitReminders(_ habits: [Habit], hour: Int = 9) -> [NotificationPlan] {
        var plans: [NotificationPlan] = []
        for habit in habits {
            for weekday in Set(habit.reminderWeekdays).sorted() where (1...7).contains(weekday) {
                var parts = DateComponents()
                parts.weekday = weekday
                parts.hour = hour
                parts.minute = 0
                plans.append(NotificationPlan(
                    id: NotificationCategory.habit.idPrefix + "\(habit.id)_\(weekday)",
                    category: .habit,
                    title: "\(habit.emoji) \(habit.name)",
                    body: habit.identity.isEmpty
                        ? "Time to check in on your habit."
                        : "A small vote for \(habit.identity).",
                    dateComponents: parts,
                    repeats: true
                ))
            }
        }
        return plans
    }

    /// A single daily reminder at `hour:minute`.
    public static func daily(
        category: NotificationCategory,
        id: String,
        title: String,
        body: String,
        hour: Int,
        minute: Int = 0
    ) -> NotificationPlan {
        NotificationPlan(
            id: category.idPrefix + id,
            category: category,
            title: title,
            body: body,
            dateComponents: DateComponents(hour: hour, minute: minute),
            repeats: true
        )
    }

    /// One-off reminder on a specific calendar day at `hour:00` (e.g. a
    /// subscription renewal). Returns nil for dates in the past.
    public static func onDate(
        category: NotificationCategory,
        id: String,
        title: String,
        body: String,
        date: Date,
        hour: Int = 9,
        asOf now: Date = Date()
    ) -> NotificationPlan? {
        let calendar = gregorian
        guard calendar.startOfDay(for: date) >= calendar.startOfDay(for: now) else { return nil }
        var parts = calendar.dateComponents([.year, .month, .day], from: date)
        parts.hour = hour
        parts.minute = 0
        return NotificationPlan(
            id: category.idPrefix + id,
            category: category,
            title: title,
            body: body,
            dateComponents: parts,
            repeats: false
        )
    }
}

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

    /// Spaced daily water nudges through the day. Repeating triggers can't see
    /// runtime intake, so this is a gentle fixed cadence, not goal-aware.
    public static func waterReminders(hours: [Int] = [10, 13, 16, 19]) -> [NotificationPlan] {
        hours.filter { (0...23).contains($0) }.map { hour in
            NotificationPlan(
                id: NotificationCategory.water.idPrefix + "\(hour)",
                category: .water,
                title: "Time for some water 💧",
                body: "A glass now keeps you on track for the day.",
                dateComponents: DateComponents(hour: hour, minute: 0),
                repeats: true
            )
        }
    }

    /// Default dose times per frequency; a daily repeating reminder each.
    static func doseHours(for frequency: MedFrequency) -> [Int] {
        switch frequency {
        case .once: [9]
        case .twice: [9, 21]
        case .threePerDay: [9, 14, 21]
        }
    }

    /// Daily reminders per medication at its frequency's default dose times.
    public static func medicationReminders(_ medications: [Medication]) -> [NotificationPlan] {
        var plans: [NotificationPlan] = []
        for med in medications where !med.name.trimmingCharacters(in: .whitespaces).isEmpty {
            for hour in doseHours(for: med.frequency) {
                plans.append(NotificationPlan(
                    id: NotificationCategory.medication.idPrefix + "\(med.id)_\(hour)",
                    category: .medication,
                    title: "💊 \(med.name)",
                    body: med.dosage.isEmpty
                        ? "Time for your dose."
                        : "Take your \(med.dosage) dose.",
                    dateComponents: DateComponents(hour: hour, minute: 0),
                    repeats: true
                ))
            }
        }
        return plans
    }

    /// A daily wind-down nudge `minutesBefore` the scheduled bedtime. Returns
    /// nil unless the user turned bedtime reminders on in Rest.
    public static func bedtime(_ schedule: SleepSchedule, minutesBefore: Int = 30) -> NotificationPlan? {
        guard schedule.remindersEnabled else { return nil }
        let total = schedule.bedtimeHour * 60 + schedule.bedtimeMinute - minutesBefore
        let normalized = ((total % 1440) + 1440) % 1440
        return NotificationPlan(
            id: NotificationCategory.bedtime.idPrefix + "main",
            category: .bedtime,
            title: "Wind down for bed 🌙",
            body: "Lights out around \(schedule.bedtimeLabel) — start easing off screens.",
            dateComponents: DateComponents(hour: normalized / 60, minute: normalized % 60),
            repeats: true
        )
    }

    /// A one-off reminder on each plant's next watering day (clamped to today
    /// when overdue). Re-run after watering re-computes the next date.
    public static func plantWatering(
        _ plants: [Plant], hour: Int = 9, asOf now: Date = Date()
    ) -> [NotificationPlan] {
        let calendar = gregorian
        return plants.compactMap { plant in
            let due: Date
            if let last = plant.lastWatered {
                due = last.addingTimeInterval(Double(plant.intervalDays) * 86_400)
            } else {
                due = now
            }
            let clamped = max(calendar.startOfDay(for: due), calendar.startOfDay(for: now))
            return onDate(
                category: .plant, id: plant.id,
                title: "\(plant.emoji) Water \(plant.name)",
                body: "It's watering day — every \(plant.intervalDays) day\(plant.intervalDays == 1 ? "" : "s").",
                date: clamped, hour: hour, asOf: now
            )
        }
    }

    /// A one-off reminder `daysBefore` each active subscription's renewal.
    public static func subscriptionRenewals(
        _ subscriptions: [Subscription],
        daysBefore: Int = 1,
        hour: Int = 9,
        symbol: String = "",
        asOf now: Date = Date()
    ) -> [NotificationPlan] {
        let calendar = gregorian
        return subscriptions.compactMap { sub in
            guard sub.isActive, !sub.name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let lead = max(0, sub.daysUntilBilling(asOf: now) - daysBefore)
            guard let date = calendar.date(
                byAdding: .day, value: lead, to: calendar.startOfDay(for: now)
            ) else { return nil }
            let amount = sub.amount == sub.amount.rounded()
                ? String(format: "%.0f", sub.amount)
                : String(format: "%.2f", sub.amount)
            return onDate(
                category: .subscription, id: sub.id,
                title: "\(sub.emoji) \(sub.name) renews soon",
                body: "\(symbol)\(amount) bills on the \(sub.billingDay)\(ordinalSuffix(sub.billingDay)).",
                date: date, hour: hour, asOf: now
            )
        }
    }

    private static func ordinalSuffix(_ day: Int) -> String {
        switch (day % 100, day % 10) {
        case (11, _), (12, _), (13, _): "th"
        case (_, 1): "st"
        case (_, 2): "nd"
        case (_, 3): "rd"
        default: "th"
        }
    }
}

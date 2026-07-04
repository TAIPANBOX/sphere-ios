import Foundation

public enum Urgency: Int, Sendable, Comparable {
    case urgent = 0
    case important = 1
    case daily = 2

    public static func < (lhs: Urgency, rhs: Urgency) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct FocusItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let emoji: String
    public let title: String
    public let subtitle: String
    public let sphere: SphereType
    public let urgency: Urgency
    public let tag: String?

    public init(
        id: String,
        emoji: String,
        title: String,
        subtitle: String,
        sphere: SphereType,
        urgency: Urgency,
        tag: String? = nil
    ) {
        self.id = id
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
        self.sphere = sphere
        self.urgency = urgency
        self.tag = tag
    }
}

/// Today's Focus aggregation ported from the Flutter home tab
/// (`_buildFocusItems`), including the wave-2 sources: contacts' birthdays
/// and home-sphere tasks.
public enum FocusBuilder {
    public static func build(
        careerTasks: [CareerTask],
        goals: [Goal],
        metrics: HealthMetrics?,
        contacts: [Contact] = [],
        homeTasks: [HomeTask] = [],
        hasMeditatedToday: Bool = false,
        stepsGoal: Int = HealthStore.stepsGoal,
        now: Date = Date()
    ) -> [FocusItem] {
        var items: [FocusItem] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        for task in careerTasks where task.status != .done && task.isOverdue(asOf: now) {
            guard let dueDate = task.dueDate else { continue }
            let daysAgo = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: dueDate), to: today
            ).day ?? 0
            items.append(FocusItem(
                id: "overdue_\(task.id)",
                emoji: "⚠️",
                title: task.title,
                subtitle: "\(task.project) · Overdue by \(daysAgo) day\(daysAgo == 1 ? "" : "s")",
                sphere: .career,
                urgency: .urgent,
                tag: "Overdue"
            ))
        }

        for task in careerTasks
        where task.status != .done && !task.isOverdue(asOf: now) && task.priority == .urgent {
            items.append(FocusItem(
                id: "urgent_\(task.id)",
                emoji: "🔴",
                title: task.title,
                subtitle: task.project + dueSuffix(task.dueDate),
                sphere: .career,
                urgency: .urgent,
                tag: "Urgent"
            ))
        }

        let overdueHome = homeTasks.filter { task in
            guard task.status == .todo, let dueDate = task.dueDate else { return false }
            return calendar.startOfDay(for: dueDate) < today
        }
        for task in overdueHome {
            items.append(FocusItem(
                id: "home_overdue_\(task.id)",
                emoji: task.category.emoji,
                title: task.title,
                subtitle: "\(task.category.label) · Overdue",
                sphere: .home,
                urgency: .urgent,
                tag: "Overdue"
            ))
        }

        let highTasks = careerTasks
            .filter { $0.status != .done && !$0.isOverdue(asOf: now) && $0.priority == .high }
            .prefix(2)
        for task in highTasks {
            items.append(FocusItem(
                id: "high_\(task.id)",
                emoji: "🟠",
                title: task.title,
                subtitle: task.project + dueSuffix(task.dueDate),
                sphere: .career,
                urgency: .important,
                tag: "High"
            ))
        }

        let birthdays = contacts
            .filter { ($0.daysUntilBirthday(asOf: now) ?? 999) <= 3 }
            .sorted { ($0.daysUntilBirthday(asOf: now) ?? 999) < ($1.daysUntilBirthday(asOf: now) ?? 999) }
        for contact in birthdays {
            let days = contact.daysUntilBirthday(asOf: now) ?? 0
            items.append(FocusItem(
                id: "bday_\(contact.id)",
                emoji: "🎂",
                title: "\(contact.name)'s Birthday",
                subtitle: days == 0 ? "Today! 🎉" : days == 1 ? "Tomorrow" : "In \(days) days",
                sphere: .relationships,
                urgency: days == 0 ? .urgent : .important,
                tag: days == 0 ? "Today" : days == 1 ? "Tomorrow" : nil
            ))
        }

        let stuckGoals = goals
            .filter { $0.status == .active && $0.progressPercent < 20 }
            .prefix(2)
        for goal in stuckGoals {
            items.append(FocusItem(
                id: "goal_\(goal.id)",
                emoji: goal.emoji,
                title: goal.title,
                subtitle: "\(goal.progressPercent)% complete · needs attention",
                sphere: .goals,
                urgency: .important,
                tag: "\(goal.progressPercent)%"
            ))
        }

        let todayHome = homeTasks
            .filter { task in
                guard task.status == .todo, let dueDate = task.dueDate else { return false }
                return calendar.isDate(dueDate, inSameDayAs: now)
            }
            .prefix(2)
        for task in todayHome {
            items.append(FocusItem(
                id: "home_today_\(task.id)",
                emoji: task.category.emoji,
                title: task.title,
                subtitle: "\(task.category.label) · Scheduled today",
                sphere: .home,
                urgency: .daily,
                tag: "Today"
            ))
        }

        if !hasMeditatedToday {
            items.append(FocusItem(
                id: "mindfulness_daily",
                emoji: "🧘",
                title: "Daily meditation",
                subtitle: "10 min · not done yet today",
                sphere: .mindfulness,
                urgency: .daily,
                tag: "Daily"
            ))
        }

        if let metrics, metrics.steps < stepsGoal {
            let remaining = stepsGoal - metrics.steps
            items.append(FocusItem(
                id: "health_steps",
                emoji: "👟",
                title: "Reach daily step goal",
                subtitle: "\(remaining.formatted()) steps left · ~\(max(remaining / 100, 1)) min walk",
                sphere: .health,
                urgency: .daily
            ))
        }

        let fallbacks = [
            FocusItem(
                id: "hydration", emoji: "💧", title: "Stay hydrated",
                subtitle: "8 glasses a day · track your intake",
                sphere: .rest, urgency: .daily
            ),
            FocusItem(
                id: "posture", emoji: "🧍", title: "Posture check",
                subtitle: "Sit straight · take a short break",
                sphere: .health, urgency: .daily
            ),
            FocusItem(
                id: "journal", emoji: "📓", title: "Daily reflection",
                subtitle: "5 min · write down one insight today",
                sphere: .mindfulness, urgency: .daily
            ),
            FocusItem(
                id: "learning", emoji: "📖", title: "Learn something new",
                subtitle: "15 min reading or a lesson",
                sphere: .learning, urgency: .daily
            ),
            FocusItem(
                id: "gratitude", emoji: "🙏", title: "Gratitude moment",
                subtitle: "Note 3 things you are grateful for",
                sphere: .mindfulness, urgency: .daily
            ),
        ]
        let existingIds = Set(items.map(\.id))
        for fallback in fallbacks where items.count < 5 {
            if !existingIds.contains(fallback.id) {
                items.append(fallback)
            }
        }

        return items.sorted { $0.urgency < $1.urgency }
    }

    private static func dueSuffix(_ dueDate: Date?) -> String {
        guard let dueDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return " · due \(formatter.string(from: dueDate))"
    }
}

import Foundation

/// One proactive suggestion. `id` is stable per rule so cooldowns persist.
public struct Nudge: Sendable, Equatable {
    public let id: String
    public let title: String
    public let body: String
    public let cooldownDays: Int
    /// Higher wins when several nudges fire at once.
    public let priority: Int

    public init(id: String, priority: Int, title: String, body: String, cooldownDays: Int) {
        self.id = id
        self.title = title
        self.body = body
        self.cooldownDays = cooldownDays
        self.priority = priority
    }
}

/// A snapshot of the signals the nudge rules read — assembled from the sphere
/// stores so the rules stay pure and testable.
public struct NudgeContext: Sendable {
    public var now: Date
    public var hour: Int
    /// Recent daily stress (1–10), most recent last.
    public var recentStress: [Int]
    public var meditatedToday: Bool
    public var meditationStreak: Int
    public var monthlyBudgetTotal: Double
    public var spentThisMonth: Double
    public var dayOfMonth: Int
    public var staleContact: (name: String, days: Int)?
    public var thirstyPlant: (name: String, daysOverdue: Int)?
    public var sleepDebtHours: Double

    public init(
        now: Date, hour: Int, recentStress: [Int] = [], meditatedToday: Bool = false,
        meditationStreak: Int = 0, monthlyBudgetTotal: Double = 0, spentThisMonth: Double = 0,
        dayOfMonth: Int = 1, staleContact: (name: String, days: Int)? = nil,
        thirstyPlant: (name: String, daysOverdue: Int)? = nil, sleepDebtHours: Double = 0
    ) {
        self.now = now
        self.hour = hour
        self.recentStress = recentStress
        self.meditatedToday = meditatedToday
        self.meditationStreak = meditationStreak
        self.monthlyBudgetTotal = monthlyBudgetTotal
        self.spentThisMonth = spentThisMonth
        self.dayOfMonth = dayOfMonth
        self.staleContact = staleContact
        self.thirstyPlant = thirstyPlant
        self.sleepDebtHours = sleepDebtHours
    }
}

/// Pure, pattern-triggered nudge rules (N3). Each returns a nudge when its
/// condition holds; the scheduler decides which (if any) to deliver.
public enum NudgeEngine {
    public static func evaluate(_ context: NudgeContext) -> [Nudge] {
        var nudges: [Nudge] = []

        // Evening: don't let a meditation streak lapse.
        if context.hour >= 18, context.meditationStreak >= 3, !context.meditatedToday {
            nudges.append(Nudge(
                id: "streak_lapse", priority: 90,
                title: "Keep your streak",
                body: "Your \(context.meditationStreak)-day meditation streak is alive — a few minutes keeps it going.",
                cooldownDays: 1
            ))
        }

        // Stress high 3+ days running and no meditation today.
        if context.recentStress.count >= 3, context.recentStress.suffix(3).allSatisfy({ $0 >= 7 }),
           !context.meditatedToday {
            nudges.append(Nudge(
                id: "stress_relief", priority: 80,
                title: "Stress has been high",
                body: "A few stressful days in a row. A short breather might reset things.",
                cooldownDays: 3
            ))
        }

        // Budget nearly gone with days left in the month.
        if context.monthlyBudgetTotal > 0,
           context.spentThisMonth >= 0.9 * context.monthlyBudgetTotal,
           context.dayOfMonth < 24 {
            nudges.append(Nudge(
                id: "budget_warning", priority: 70,
                title: "Budget running low",
                body: "You've used most of this month's budget with a week or more to go.",
                cooldownDays: 7
            ))
        }

        // Meaningful sleep debt.
        if context.sleepDebtHours > 5 {
            nudges.append(Nudge(
                id: "sleep_debt", priority: 60,
                title: "Sleep debt building",
                body: "You're about \(Int(context.sleepDebtHours))h short on sleep this week. An early night would help.",
                cooldownDays: 3
            ))
        }

        // A friendship going cold.
        if let contact = context.staleContact {
            nudges.append(Nudge(
                id: "stale_contact", priority: 50,
                title: "Reconnect",
                body: "It's been \(contact.days) days since you talked to \(contact.name).",
                cooldownDays: 5
            ))
        }

        // A thirsty plant.
        if let plant = context.thirstyPlant, plant.daysOverdue >= 2 {
            nudges.append(Nudge(
                id: "plant_water", priority: 40,
                title: "Thirsty plant",
                body: "\(plant.name) is \(plant.daysOverdue) days overdue for water.",
                cooldownDays: 2
            ))
        }

        return nudges
    }
}

/// Applies cooldown per rule and a global cap of one nudge per day.
public enum NudgeScheduler {
    public static func select(
        candidates: [Nudge], lastFired: [String: Date], now: Date = Date()
    ) -> Nudge? {
        // Global cap: at most one nudge per day.
        let today = DayKey.make(now)
        if lastFired.values.contains(where: { DayKey.make($0) == today }) { return nil }

        let calendar = DayKey.calendar
        let eligible = candidates.filter { nudge in
            guard let fired = lastFired[nudge.id] else { return true }
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: fired), to: calendar.startOfDay(for: now)
            ).day ?? 0
            return days >= nudge.cooldownDays
        }
        return eligible.max { $0.priority < $1.priority }
    }
}

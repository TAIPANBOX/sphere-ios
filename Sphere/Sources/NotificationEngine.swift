import Foundation
import UserNotifications
import SphereCore

/// Schedules local notifications from platform-agnostic `NotificationPlan`s.
/// Syncing is idempotent per category: every managed category is fully
/// cleared and rebuilt, so edits and removals are always reflected.
///
/// Permission is requested lazily — only the first time a sync actually has
/// something to schedule, never on a bare install / welcome screen.
enum NotificationEngine {
    /// - Parameters:
    ///   - plans: the desired notifications (any categories).
    ///   - categories: the categories this sync fully manages; their existing
    ///     pending requests are cleared even when `plans` has none for them.
    static func sync(_ plans: [NotificationPlan], categories: Set<NotificationCategory>) async {
        let center = UNUserNotificationCenter.current()

        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            guard !plans.isEmpty else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        let prefixes = categories.map(\.idPrefix)
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { id in prefixes.contains { id.hasPrefix($0) } }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            // Carry the action category + payload so the reminder can be
            // completed from the wrist / lock screen without opening the app.
            if let categoryID = plan.actionCategoryIdentifier {
                content.categoryIdentifier = categoryID
            }
            if !plan.userInfo.isEmpty {
                content.userInfo = plan.userInfo
            }
            let request = UNNotificationRequest(
                identifier: plan.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: plan.dateComponents, repeats: plan.repeats
                )
            )
            try? await center.add(request)
        }
    }

    /// Registers the actionable `UNNotificationCategory` set once at launch.
    /// Actions are foreground-safe (`.authenticationRequired` off) so tapping
    /// them completes the reminder in the background; mirrored watch actions
    /// route their response to this same phone-side handler.
    static func registerCategories() {
        let logWater = UNNotificationAction(
            identifier: NotificationAction.logWater,
            title: "Log a glass", options: []
        )
        let snoozeWater = UNNotificationAction(
            identifier: NotificationAction.snoozeWater,
            title: "Snooze 30 min", options: []
        )
        let markMed = UNNotificationAction(
            identifier: NotificationAction.markMedicationTaken,
            title: "Mark taken", options: []
        )
        let markPlant = UNNotificationAction(
            identifier: NotificationAction.markPlantWatered,
            title: "Mark watered", options: []
        )
        let markHabit = UNNotificationAction(
            identifier: NotificationAction.markHabitDone,
            title: "Done", options: []
        )

        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(
                identifier: NotificationAction.waterCategory,
                actions: [logWater, snoozeWater],
                intentIdentifiers: [], options: []
            ),
            UNNotificationCategory(
                identifier: NotificationAction.medicationCategory,
                actions: [markMed], intentIdentifiers: [], options: []
            ),
            UNNotificationCategory(
                identifier: NotificationAction.plantCategory,
                actions: [markPlant], intentIdentifiers: [], options: []
            ),
            UNNotificationCategory(
                identifier: NotificationAction.habitCategory,
                actions: [markHabit], intentIdentifiers: [], options: []
            ),
        ]
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    /// Schedules a one-off water reminder 30 minutes out (the "Snooze" action).
    /// Uses a fixed identifier so repeated snoozes coalesce rather than pile up.
    static func scheduleWaterSnooze(after seconds: TimeInterval = 30 * 60) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time for some water 💧"
        content.body = "A glass now keeps you on track for the day."
        content.sound = .default
        content.categoryIdentifier = NotificationAction.waterCategory
        let request = UNNotificationRequest(
            identifier: NotificationCategory.water.idPrefix + "snooze",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        try? await center.add(request)
    }
}

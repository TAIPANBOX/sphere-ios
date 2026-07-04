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
}

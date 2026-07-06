import Foundation
import UserNotifications

/// `UNUserNotificationCenterDelegate` that routes notification action taps —
/// from the iPhone lock screen or a mirrored Apple Watch notification, both of
/// which deliver their response to this phone-side handler — into the
/// `AppContainer` store writes. Wired in `AppContainer.init`.
///
/// `@unchecked Sendable`: the only stored state is a weak `AppContainer`
/// reference set once on the main actor before the delegate is installed.
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private weak var container: AppContainer?

    init(container: AppContainer) {
        self.container = container
        super.init()
    }

    /// Show banners even while the app is foregrounded, so a reminder that
    /// fires with the app open is still actionable.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        // The default tap / dismiss just opens the app; nothing to complete.
        guard action != UNNotificationDefaultActionIdentifier,
              action != UNNotificationDismissActionIdentifier
        else { return }
        // Extract only the Sendable string payload here (in the task context)
        // rather than sending the non-Sendable `[AnyHashable: Any]` userInfo
        // across the actor boundary.
        let userInfo = response.notification.request.content.userInfo
        let payload = Dictionary(uniqueKeysWithValues: userInfo.compactMap {
            key, value -> (String, String)? in
            guard let key = key as? String, let value = value as? String else { return nil }
            return (key, value)
        })
        await container?.applyNotificationAction(action, payload: payload)
    }
}

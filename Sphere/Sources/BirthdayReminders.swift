import Foundation
import UserNotifications
import SphereCore

/// Schedules a yearly local notification at 09:00 on each contact's
/// birthday. Rescheduling is idempotent: all sphere birthday requests are
/// replaced on every sync, so removals and edits are picked up.
enum BirthdayReminders {
    private static let prefix = "bday_"

    static func sync(contacts: [Contact]) async {
        let withBirthdays = contacts.filter { $0.birthday != nil }
        let center = UNUserNotificationCenter.current()

        // Don't prompt for notification permission until there is actually a
        // birthday to remind about — a bare install has no contacts, so the
        // prompt shouldn't appear on the welcome screen.
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            guard !withBirthdays.isEmpty else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        for contact in withBirthdays {
            guard let birthday = contact.birthday else { continue }
            var parts = calendar.dateComponents([.month, .day], from: birthday)
            parts.hour = 9

            let content = UNMutableNotificationContent()
            content.title = "\(contact.name)'s birthday is today 🎂"
            content.body = "Send some love — your Relationships agent has gift ideas."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: prefix + contact.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
            )
            try? await center.add(request)
        }
    }
}

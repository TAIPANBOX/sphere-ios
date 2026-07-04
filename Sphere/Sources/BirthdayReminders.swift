import Foundation
import SphereCore

/// Yearly birthday reminders, now a thin client of the general
/// `NotificationEngine`: it just builds the plans and hands them over.
/// Gated by the profile's per-category opt-in (birthdays default on).
enum BirthdayReminders {
    static func sync(contacts: [Contact], enabled: Bool = true) async {
        let plans = enabled
            ? NotificationPlanBuilder.birthdays(contacts.filter { $0.birthday != nil })
            : []
        await NotificationEngine.sync(plans, categories: [.birthday])
    }
}

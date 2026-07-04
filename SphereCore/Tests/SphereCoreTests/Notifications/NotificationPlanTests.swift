import Foundation
import Testing
@testable import SphereCore

@Suite("NotificationPlanBuilder")
struct NotificationPlanTests {
    private let cal = { () -> Calendar in
        var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func birthdaysBuildYearlyNinaAmPlans() {
        let contacts = [
            Contact(id: "c1", name: "Iryna", birthday: date(1990, 3, 14)),
            Contact(id: "c2", name: "No Bday"),
        ]
        let plans = NotificationPlanBuilder.birthdays(contacts)
        #expect(plans.count == 1)
        let plan = plans[0]
        #expect(plan.id == "birthday_c1")
        #expect(plan.category == .birthday)
        #expect(plan.repeats)
        #expect(plan.dateComponents.month == 3)
        #expect(plan.dateComponents.day == 14)
        #expect(plan.dateComponents.hour == 9)
        #expect(plan.dateComponents.year == nil) // yearly, not year-pinned
    }

    @Test func dailyReminderCarriesTimeAndPrefix() {
        let plan = NotificationPlanBuilder.daily(
            category: .morningBrief, id: "main",
            title: "Your brief is ready", body: "Tap to read", hour: 8, minute: 30
        )
        #expect(plan.id == "morningBrief_main")
        #expect(plan.dateComponents.hour == 8)
        #expect(plan.dateComponents.minute == 30)
        #expect(plan.repeats)
    }

    @Test func onDateSkipsPastAndPinsYear() {
        let now = date(2026, 7, 4)
        #expect(
            NotificationPlanBuilder.onDate(
                category: .subscription, id: "netflix", title: "Renews", body: "£12",
                date: date(2026, 6, 1), asOf: now
            ) == nil
        )
        let future = NotificationPlanBuilder.onDate(
            category: .subscription, id: "netflix", title: "Renews", body: "£12",
            date: date(2026, 8, 1), asOf: now
        )
        let plan = try! #require(future)
        #expect(plan.dateComponents.year == 2026)
        #expect(plan.dateComponents.month == 8)
        #expect(!plan.repeats)
    }

    @Test func categoryDefaultsOnlyBirthdayOn() {
        #expect(NotificationCategory.birthday.defaultOn)
        #expect(!NotificationCategory.water.defaultOn)
        #expect(NotificationCategory.water.idPrefix == "water_")
    }
}

@Suite("UserProfile tolerant decoding + profile-v2")
struct UserProfileV2Tests {
    @Test func decodesLegacyJsonMissingNewFields() throws {
        // A profile saved before profile-v2 — no notificationPrefs/wellbeing.
        let legacy = """
        {"name":"Yurii","gender":"female","onboarded":true,
         "healthConditions":["hypertension"]}
        """
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(legacy.utf8))
        #expect(profile.name == "Yurii")
        #expect(profile.gender == .female)
        #expect(profile.onboarded)
        #expect(profile.healthConditions == ["hypertension"])
        // New fields default cleanly instead of throwing.
        #expect(profile.notificationPrefs.isEmpty)
        #expect(profile.wellbeingMode == .normal)
        #expect(!profile.appLockEnabled)
        #expect(profile.vacationDaysPerYear == nil)
    }

    @Test func roundTripsNewFields() throws {
        let until = Date(timeIntervalSince1970: 1_800_000_000)
        var profile = UserProfile(name: "A")
        profile.notificationPrefs = ["water": true, "birthday": false]
        profile.wellbeingMode = .sick
        profile.wellbeingUntil = until
        profile.vacationDaysPerYear = 25
        profile.appLockEnabled = true

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        #expect(decoded == profile)
        #expect(decoded.notificationEnabled("water", default: false))
        #expect(!decoded.notificationEnabled("birthday", default: true))
        #expect(decoded.notificationEnabled("plant", default: true)) // unset → fallback
    }

    @Test func agentContextIncludesAboutAndCity() {
        var profile = UserProfile(name: "Yurii")
        profile.city = "Kyiv"
        profile.aboutMe = "Founder building an AI life app"
        let context = profile.agentContext()
        #expect(context.contains("City: Kyiv"))
        #expect(context.contains("About: Founder building an AI life app"))
    }

    @Test func wellbeingPauseRespectsUntilDate() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var p = UserProfile()
        #expect(!p.isWellbeingPaused(asOf: now))

        p.wellbeingMode = .vacation
        p.wellbeingUntil = now.addingTimeInterval(86_400)
        #expect(p.isWellbeingPaused(asOf: now))
        // Expired.
        #expect(!p.isWellbeingPaused(asOf: now.addingTimeInterval(172_800)))
        // No end date → indefinite.
        p.wellbeingUntil = nil
        #expect(p.isWellbeingPaused(asOf: now))
    }
}

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

    @Test func waterRemindersRepeatDailyAtGivenHours() {
        let plans = NotificationPlanBuilder.waterReminders(hours: [10, 16, 99])
        #expect(plans.map(\.id) == ["water_10", "water_16"]) // 99 dropped
        #expect(plans.allSatisfy { $0.repeats && $0.category == .water })
        #expect(plans[0].dateComponents.hour == 10)
    }

    @Test func medicationRemindersMapFrequencyToDoseTimes() {
        let meds = [
            Medication(id: "m1", name: "Vitamin D", dosage: "1000 IU", frequency: .once, takenDates: []),
            Medication(id: "m2", name: "Antibiotic", dosage: "", frequency: .threePerDay, takenDates: []),
            Medication(id: "m3", name: "  ", dosage: "x", frequency: .twice, takenDates: []), // blank → skipped
        ]
        let plans = NotificationPlanBuilder.medicationReminders(meds)
        #expect(plans.map(\.id) == [
            "medication_m1_9",
            "medication_m2_9", "medication_m2_14", "medication_m2_21",
        ])
        #expect(plans[0].body.contains("1000 IU"))
        #expect(plans[1].body == "Time for your dose.") // empty dosage fallback
    }

    @Test func bedtimeWindsDownBeforeBedtimeWhenEnabled() {
        var schedule = SleepSchedule(bedtimeHour: 23, bedtimeMinute: 0, remindersEnabled: true)
        let plan = try! #require(NotificationPlanBuilder.bedtime(schedule, minutesBefore: 30))
        #expect(plan.id == "bedtime_main")
        #expect(plan.dateComponents.hour == 22)
        #expect(plan.dateComponents.minute == 30)
        #expect(plan.repeats)

        // Wraps past midnight: 00:15 bedtime, 30 min before → 23:45.
        schedule = SleepSchedule(bedtimeHour: 0, bedtimeMinute: 15, remindersEnabled: true)
        let wrapped = try! #require(NotificationPlanBuilder.bedtime(schedule, minutesBefore: 30))
        #expect(wrapped.dateComponents.hour == 23)
        #expect(wrapped.dateComponents.minute == 45)
    }

    @Test func bedtimeNilWhenDisabled() {
        let schedule = SleepSchedule(bedtimeHour: 23, remindersEnabled: false)
        #expect(NotificationPlanBuilder.bedtime(schedule) == nil)
    }

    @Test func plantWateringSchedulesNextDueClampedToToday() {
        let now = date(2026, 7, 4)
        let plants = [
            Plant(id: "p1", name: "Fern", lastWatered: nil, intervalDays: 3),               // never → today
            Plant(id: "p2", name: "Cactus", lastWatered: date(2026, 7, 3), intervalDays: 5), // due 7/8
            Plant(id: "p3", name: "Ivy", lastWatered: date(2026, 6, 20), intervalDays: 3),   // overdue → today
        ]
        let plans = NotificationPlanBuilder.plantWatering(plants, asOf: now)
        #expect(plans.map(\.id) == ["plant_p1", "plant_p2", "plant_p3"])
        #expect(plans[0].dateComponents.day == 4)   // never watered → today
        #expect(plans[1].dateComponents.day == 8)   // 7/3 + 5d
        #expect(plans[2].dateComponents.day == 4)   // overdue clamped to today
        #expect(plans.allSatisfy { !$0.repeats && $0.category == .plant })
    }

    @Test func subscriptionRenewalsLeadTimeAndSkipInactive() {
        let now = date(2026, 7, 4)
        let subs = [
            Subscription(id: "s1", name: "Netflix", amount: 12.99, billingDay: 10),           // bills 7/10 → remind 7/9
            Subscription(id: "s2", name: "Gym", amount: 30, billingDay: 1, isActive: false),  // inactive → skip
        ]
        let plans = NotificationPlanBuilder.subscriptionRenewals(subs, daysBefore: 1, symbol: "£", asOf: now)
        #expect(plans.map(\.id) == ["subscription_s1"])
        #expect(plans[0].dateComponents.day == 9)
        #expect(plans[0].body.contains("£12.99"))
        #expect(plans[0].body.contains("10th"))
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

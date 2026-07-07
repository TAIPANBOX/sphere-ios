#if DEBUG
import Foundation
import SphereCore

/// DEBUG-only demo-data seeder: fills every sphere as if "Max" had tracked
/// his life in Sphere for ~180 days. Triggered by launch arguments only —
/// never runs in a release build (the whole file is `#if DEBUG`).
///
/// - `-DemoSeed`: seeds once (guarded by `Prefs.demoSeeded` in UserDefaults),
///   then refreshes the widget snapshot and reminders.
/// - `-WipeAllData`: deletes the databases, offline cache, and UserDefaults
///   domain *before* `AppContainer` opens anything, so the app boots fresh
///   into onboarding. Handled separately in `SphereApp` before `AppContainer()`
///   is constructed.
///
/// Every write goes through the real `@MainActor` store APIs on `container`
/// so day-keys, streak math, and derived state stay consistent with what the
/// app computes at runtime — this file never touches SQL directly.
enum DemoSeed {
    /// Runs the full seed exactly once per install (guarded by
    /// `Prefs.demoSeeded`). No-op if already seeded.
    @MainActor
    static func runIfNeeded(container: AppContainer) async {
        guard !UserDefaults.standard.bool(forKey: Prefs.demoSeeded) else { return }
        let start = Date()
        await run(container: container)
        UserDefaults.standard.set(true, forKey: Prefs.demoSeeded)
        container.refreshWidget()
        await container.syncReminders()
        let elapsed = Date().timeIntervalSince(start)
        print("[DemoSeed] Seeded demo data in \(String(format: "%.2f", elapsed))s")
    }

    /// Deletes the sphere databases (+ WAL/SHM sidecars), the offline-cache
    /// directory, and every app-domain UserDefaults key. Must run before
    /// `AppContainer()` is constructed (before any database is opened).
    static func wipeAllData() {
        let fm = FileManager.default
        let dbDir = DatabaseLocation.resolve()

        let bases = ["sphere.db", "sphere.engram.db"]
        let suffixes = ["", "-wal", "-shm"]
        for base in bases {
            for suffix in suffixes {
                let url = dbDir.appendingPathComponent(base + suffix)
                try? fm.removeItem(at: url)
            }
        }
        try? fm.removeItem(at: dbDir.appendingPathComponent("cache"))

        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        print("[DemoSeed] Wiped all local data (fresh boot expected).")
    }

    // MARK: - Seed orchestration

    @MainActor
    private static func run(container: AppContainer) async {
        var rng = SeededGenerator(seed: 0x5EED_5EED)
        let today = Calendar.current.startOfDay(for: Date())
        let world = DemoWorld(today: today)

        // Health/Rest/Mindfulness get *fresh* store instances pointed at the
        // same database, constructed with no HealthKit provider. The real
        // `container.health`/`.rest`/`.mindfulness` are wired to the real
        // `HealthKitService`, and this build has no HealthKit entitlement
        // (unsigned/CI, and even on a signed device the user hasn't granted
        // authorization yet) — `HKHealthStore.isHealthDataAvailable()` still
        // returns true on a real device, so every write-back call
        // (`store.save`) would proceed and block for a long time (or forever)
        // waiting on an unauthorized HealthKit XPC round trip, once per log
        // entry across 180 days. Writing through a provider-less store avoids
        // that entirely; both instances share the same `AppDatabase`, so the
        // data lands in the same tables and `container.loadAll()` at the end
        // reloads the real stores from it.
        let health = HealthStore(database: container.database, engram: container.engram)
        let rest = RestStore(database: container.database, engram: container.engram)
        let mindfulness = MindfulnessStore(database: container.database, engram: container.engram)

        await seedProfile(container: container)
        await seedHealth(health: health, world: world, rng: &rng)
        await seedRest(rest: rest, world: world, rng: &rng)
        await seedMindfulness(mindfulness: mindfulness, world: world, rng: &rng)
        await seedFinance(container: container, world: world, rng: &rng)
        await seedCareer(container: container, world: world, rng: &rng)
        await seedLearning(container: container, world: world, rng: &rng)
        await seedGoals(container: container, world: world, rng: &rng)
        await seedRelationships(container: container, world: world, rng: &rng)
        await seedHobbies(container: container, world: world, rng: &rng)
        await seedTravel(container: container, world: world, rng: &rng)
        await seedCreativity(container: container, world: world, rng: &rng)
        await seedHomeSphere(container: container, world: world, rng: &rng)

        // Reload every store so in-memory published state matches what was
        // just written (mirrors AppContainer.loadAll's own sequence).
        await container.loadAll()
    }
}

/// Shared time anchors for the ~180-day world.
private struct DemoWorld {
    let today: Date
    let days = 180

    /// `daysAgo` days before `today` at local midnight.
    func day(_ daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) ?? today
    }

    /// `daysAgo` days before `today`, at a specific hour/minute (for
    /// timestamps that matter, like a bedtime or a workout time).
    func day(_ daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let base = day(daysAgo)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    func isWeekend(_ daysAgo: Int) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: day(daysAgo))
        return weekday == 1 || weekday == 7
    }
}

/// Deterministic small LCG so repeated seed runs produce the same world.
/// Conforms to `RandomNumberGenerator` so it drops into `Int.random(in:using:)`
/// etc. Not cryptographic — purely for reproducible demo data.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        // splitmix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension RandomNumberGenerator {
    mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &self) < probability
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[Int.random(in: 0..<items.count, using: &self)]
    }
}

// MARK: - Profile

extension DemoSeed {
    @MainActor
    fileprivate static func seedProfile(container: AppContainer) async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let birthday = calendar.date(from: DateComponents(year: 1988, month: 4, day: 12))

        try? await container.profile.update { profile in
            profile.name = "Max"
            profile.city = "London"
            profile.aboutMe = "Software engineer who's trying to keep the rest of life as "
                + "well-tended as the codebase."
            profile.birthDate = birthday
            profile.gender = .male
            profile.dietaryRestrictions = ["vegetarian"]
            profile.foodAllergies = ["nuts"]
            profile.healthConditions = []
            profile.onboarded = true
        }
    }
}

// MARK: - Health

extension DemoSeed {
    @MainActor
    fileprivate static func seedHealth(
        health: HealthStore, world: DemoWorld, rng: inout SeededGenerator
    ) async {
        // Daily water, 3-8 glasses, backdated per day via repeated addWaterGlass(on:).
        for daysAgo in stride(from: world.days, through: 0, by: -1) {
            let date = world.day(daysAgo, hour: 20)
            let glasses = Int.random(in: 3...8, using: &rng)
            for _ in 0..<glasses {
                try? await health.addWaterGlass(on: date)
            }
        }

        // Weight 2x/week, drifting 84 -> 79 kg across the 180 days.
        let weighDays = stride(from: world.days, through: 0, by: -3).map { $0 }
        for daysAgo in weighDays {
            let progress = 1 - Double(daysAgo) / Double(world.days)
            let base = 84.0 - progress * 5.0
            let noise = Double.random(in: -0.4...0.4, using: &rng)
            try? await health.logWeight(kg: (base + noise * 10).rounded() / 10, on: world.day(daysAgo, hour: 7))
        }

        // Workouts 3x/week, alternating running/gym/walking, 25-70 min.
        let workoutTypes: [WorkoutType] = [.running, .gym, .walking]
        var workoutIndex = 0
        for daysAgo in stride(from: world.days, through: 0, by: -1) {
            guard daysAgo % 7 == 1 || daysAgo % 7 == 3 || daysAgo % 7 == 5 else { continue }
            guard rng.chance(0.85) else { continue }
            let type = workoutTypes[workoutIndex % workoutTypes.count]
            workoutIndex += 1
            let minutes = Int.random(in: 25...70, using: &rng)
            let workout = Workout(
                id: "workout_\(daysAgo)",
                type: type,
                durationMinutes: minutes,
                caloriesBurned: minutes * Int.random(in: 6...10, using: &rng),
                date: world.day(daysAgo, hour: 18, minute: 30),
                note: ""
            )
            try? await health.addWorkout(workout)
        }

        // Medications: Vitamin D once-daily (~80% adherence), Magnesium.
        let vitaminD = Medication(
            id: "med_vitamind", name: "Vitamin D", dosage: "1000 IU", frequency: .once
        )
        let magnesium = Medication(
            id: "med_magnesium", name: "Magnesium", dosage: "200 mg", frequency: .once
        )
        try? await health.addMedication(vitaminD)
        try? await health.addMedication(magnesium)
        for daysAgo in stride(from: world.days, through: 0, by: -1) {
            let date = world.day(daysAgo, hour: 9)
            if rng.chance(0.8) {
                try? await health.markMedicationTaken(id: "med_vitamind", on: date)
            }
            if rng.chance(0.6) {
                try? await health.markMedicationTaken(id: "med_magnesium", on: date)
            }
        }

        // Two lab results.
        try? await health.addLabResult(LabResult(
            id: "lab_cholesterol", name: "Total Cholesterol", value: "182", unit: "mg/dL",
            refRange: "< 200", date: world.day(120, hour: 9), isNormal: true
        ))
        try? await health.addLabResult(LabResult(
            id: "lab_vitd", name: "Vitamin D", value: "28", unit: "ng/mL",
            refRange: "30-100", date: world.day(40, hour: 9), isNormal: false
        ))
    }
}

// MARK: - Rest

extension DemoSeed {
    @MainActor
    fileprivate static func seedRest(
        rest: RestStore, world: DemoWorld, rng: inout SeededGenerator
    ) async {
        try? await rest.setBedtime(hour: 23, minute: 0)
        try? await rest.setWakeTime(hour: 7, minute: 0)
        try? await rest.setGoal(hours: 8)
        if !rest.schedule.remindersEnabled {
            try? await rest.toggleReminders()
        }

        for daysAgo in stride(from: world.days, through: 0, by: -1) {
            let weekend = world.isWeekend(daysAgo)
            let hours = weekend
                ? Double.random(in: 7.0...8.6, using: &rng)
                : Double.random(in: 5.9...7.6, using: &rng)
            let recovery: RecoveryLevel
            switch hours {
            case ..<6.3: recovery = .poor
            case ..<7.0: recovery = .fair
            case ..<8.0: recovery = .good
            default: recovery = .excellent
            }
            let entry = SleepEntry(
                id: "sleep_\(daysAgo)",
                date: world.day(daysAgo, hour: 7),
                hoursSlept: (hours * 10).rounded() / 10,
                recovery: recovery,
                bedtimeHour: weekend ? 0 : 23,
                bedtimeMinute: weekend ? 30 : 15
            )
            try? await rest.add(entry)
        }

        // A few naps.
        for daysAgo in [150, 110, 75, 40, 12] {
            try? await rest.addNap(Nap(
                id: "nap_\(daysAgo)", date: world.day(daysAgo, hour: 15),
                minutes: [20, 30, 45].randomElement(using: &rng) ?? 20
            ))
        }

        // A handful of digital-detox days.
        for daysAgo in [160, 130, 95, 60, 25, 5] {
            try? await rest.toggleDetox(on: world.day(daysAgo))
        }
    }
}

// MARK: - Mindfulness

extension DemoSeed {
    @MainActor
    fileprivate static func seedMindfulness(
        mindfulness mind: MindfulnessStore, world: DemoWorld, rng: inout SeededGenerator
    ) async {
        let meditationTypes: [MeditationType] = [.breathing, .bodyScan, .visualization, .lovingKindness]

        // Meditation 4-5x/week, 10-20 min.
        for daysAgo in stride(from: world.days, through: 0, by: -1) {
            let weekday = Calendar.current.component(.weekday, from: world.day(daysAgo))
            let baseChance = (weekday == 1 || weekday == 7) ? 0.55 : 0.7
            guard rng.chance(baseChance) else { continue }
            let session = MeditationSession(
                id: "med_\(daysAgo)",
                type: rng.pick(meditationTypes),
                durationMinutes: Int.random(in: 10...20, using: &rng),
                date: world.day(daysAgo, hour: 7, minute: 30)
            )
            try? await mind.add(session)
        }

        // Daily mood 2-5, weekday-correlated (weekends trend a bit happier).
        for daysAgo in stride(from: world.days, through: 0, by: -1) {
            let weekend = world.isWeekend(daysAgo)
            let score = weekend
                ? Int.random(in: 3...5, using: &rng)
                : Int.random(in: 2...4, using: &rng)
            try? await mind.setMood(score, on: world.day(daysAgo, hour: 21))
        }

        // Journal ~3x/week, short entries.
        let journalLines = [
            "Good focus today, shipped the thing I'd been putting off.",
            "Felt a bit stretched thin — too many meetings back to back.",
            "Long walk after work, cleared my head.",
            "Proud of how the week's going so far.",
            "Slept badly, dragged through the afternoon.",
            "Quiet weekend, exactly what I needed.",
            "Good conversation with an old friend today.",
            "Frustrated with a bug for hours, finally cracked it.",
        ]
        for daysAgo in stride(from: world.days, through: 0, by: -2) {
            guard rng.chance(0.45) else { continue }
            try? await mind.addJournal(rng.pick(journalLines), on: world.day(daysAgo, hour: 22))
        }

        // A few gratitude entries.
        let gratitudeLines = [
            "A slow, sunny morning coffee.",
            "My sister calling just to check in.",
            "Finishing a good book.",
            "A great gig with the band.",
            "Getting the flat tidy for once.",
        ]
        for (i, daysAgo) in [150, 110, 80, 45, 10].enumerated() {
            try? await mind.addGratitude(gratitudeLines[i], on: world.day(daysAgo, hour: 21, minute: 30))
        }

        // Two custom affirmations.
        try? await mind.addAffirmation("I show up consistently, even on the hard days.")
        try? await mind.addAffirmation("Progress, not perfection.")
    }
}

// MARK: - Finance

extension DemoSeed {
    @MainActor
    fileprivate static func seedFinance(
        container: AppContainer, world: DemoWorld, rng: inout SeededGenerator
    ) async {
        let finance = container.finance

        try? await finance.addAccount(Account(id: "acct_checking", name: "Checking", type: .checking, balance: 2400))
        try? await finance.addAccount(Account(id: "acct_savings", name: "Savings", type: .savings, balance: 8000))

        // Monthly salary on the 1st.
        var salaryCount = 0
        for daysAgo in stride(from: world.days, through: 0, by: -1) {
            let day = Calendar.current.component(.day, from: world.day(daysAgo))
            guard day == 1 else { continue }
            salaryCount += 1
            try? await finance.add(Transaction(
                id: "txn_salary_\(daysAgo)", title: "Salary", amount: 4200,
                type: .income, category: .salary, date: world.day(daysAgo, hour: 9)
            ))
        }

        // 250+ expenses across categories with realistic amounts.
        struct ExpenseTemplate { let title: String; let category: TransactionCategory; let range: ClosedRange<Double> }
        let templates: [ExpenseTemplate] = [
            ExpenseTemplate(title: "Groceries", category: .food, range: 15...65),
            ExpenseTemplate(title: "Cafe", category: .food, range: 3...8),
            ExpenseTemplate(title: "Tube fare", category: .transport, range: 2...7),
            ExpenseTemplate(title: "Cinema", category: .entertainment, range: 10...25),
            ExpenseTemplate(title: "Electricity bill", category: .housing, range: 40...90),
            ExpenseTemplate(title: "Pharmacy", category: .health, range: 5...30),
        ]
        var expenseCount = 0
        for daysAgo in stride(from: world.days, through: 0, by: -1) {
            let date = world.day(daysAgo, hour: Int.random(in: 8...20, using: &rng))
            // Cafe most days, groceries ~2x/week, others sparser.
            if rng.chance(0.5) {
                let t = templates[1]
                try? await finance.add(Transaction(
                    id: "txn_exp_\(daysAgo)_cafe", title: t.title, amount: Double.random(in: t.range, using: &rng).rounded(toPlaces: 2),
                    type: .expense, category: t.category, date: date
                ))
                expenseCount += 1
            }
            if daysAgo % 3 == 0 {
                let t = templates[0]
                try? await finance.add(Transaction(
                    id: "txn_exp_\(daysAgo)_groceries", title: t.title, amount: Double.random(in: t.range, using: &rng).rounded(toPlaces: 2),
                    type: .expense, category: t.category, date: date
                ))
                expenseCount += 1
            }
            if daysAgo % 2 == 0 {
                let t = templates[2]
                try? await finance.add(Transaction(
                    id: "txn_exp_\(daysAgo)_transport", title: t.title, amount: Double.random(in: t.range, using: &rng).rounded(toPlaces: 2),
                    type: .expense, category: t.category, date: date
                ))
                expenseCount += 1
            }
            if rng.chance(0.12) {
                let t = templates[3]
                try? await finance.add(Transaction(
                    id: "txn_exp_\(daysAgo)_ent", title: t.title, amount: Double.random(in: t.range, using: &rng).rounded(toPlaces: 2),
                    type: .expense, category: t.category, date: date
                ))
                expenseCount += 1
            }
            if daysAgo % 30 == 15 {
                let t = templates[4]
                try? await finance.add(Transaction(
                    id: "txn_exp_\(daysAgo)_util", title: t.title, amount: Double.random(in: t.range, using: &rng).rounded(toPlaces: 2),
                    type: .expense, category: t.category, date: date
                ))
                expenseCount += 1
            }
            if rng.chance(0.08) {
                let t = templates[5]
                try? await finance.add(Transaction(
                    id: "txn_exp_\(daysAgo)_health", title: t.title, amount: Double.random(in: t.range, using: &rng).rounded(toPlaces: 2),
                    type: .expense, category: t.category, date: date
                ))
                expenseCount += 1
            }
            if expenseCount >= 260 { break }
        }

        // Budgets for 3-4 categories.
        try? await finance.setBudget(category: .food, limit: 500)
        try? await finance.setBudget(category: .transport, limit: 120)
        try? await finance.setBudget(category: .entertainment, limit: 100)
        try? await finance.setBudget(category: .housing, limit: 300)

        // Subscriptions.
        try? await finance.addSubscription(Subscription(id: "sub_netflix", name: "Netflix", emoji: "🎬", amount: 12.99, billingDay: 10))
        try? await finance.addSubscription(Subscription(id: "sub_spotify", name: "Spotify", emoji: "🎧", amount: 9.99, billingDay: 3))
        try? await finance.addSubscription(Subscription(id: "sub_icloud", name: "iCloud", emoji: "☁️", amount: 2.99, billingDay: 28))
        try? await finance.addSubscription(Subscription(id: "sub_gym", name: "Gym", emoji: "💪", amount: 35, billingDay: 1))

        // Two savings goals with progress.
        try? await finance.addSavingsGoal(SavingsGoal(id: "goal_emergency", name: "Emergency fund", emoji: "🛟", target: 10_000, saved: 6200))
        try? await finance.addSavingsGoal(SavingsGoal(id: "goal_lisbon", name: "Lisbon trip", emoji: "✈️", target: 900, saved: 540))

        _ = salaryCount
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = Foundation.pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}

// MARK: - Career

extension DemoSeed {
    @MainActor
    fileprivate static func seedCareer(
        container: AppContainer, world: DemoWorld, rng: inout SeededGenerator
    ) async {
        let career = container.career

        // ~40 tasks: 60% done over history, ~8 open, 2 overdue.
        let taskTitles = [
            "Write RFC for new service", "Fix flaky CI test", "Review PR from teammate",
            "Update onboarding docs", "Pair on the migration script", "Prep sprint demo",
            "Refactor auth module", "Investigate perf regression", "Set up staging env",
            "Triage bug backlog", "1:1 prep notes", "Update dependency versions",
            "Write postmortem", "Design API for new feature", "Load test the endpoint",
            "Clean up dead code", "Update runbook", "Interview debrief notes",
            "Draft quarterly goals", "Mentor session prep",
        ]
        var taskCount = 0
        for daysAgo in stride(from: world.days, through: 2, by: -5) {
            let title = taskTitles[taskCount % taskTitles.count]
            let done = rng.chance(0.6)
            let task = CareerTask(
                id: "task_\(taskCount)",
                title: title,
                project: rng.pick(["Platform", "Mobile", "Growth", ""]),
                priority: rng.pick([TaskPriority.low, .medium, .high]),
                status: done ? .done : .todo,
                dueDate: world.day(max(daysAgo - 3, 0), hour: 18),
                createdAt: world.day(daysAgo, hour: 9)
            )
            try? await career.add(task)
            taskCount += 1
            if taskCount >= 32 { break }
        }
        // ~8 open tasks near "now", 2 explicitly overdue.
        let openTitles = [
            "Finish the Q3 roadmap doc", "Reply to recruiter email", "Set up 1:1 with new hire",
            "Review design doc for search", "Update team wiki", "Plan offsite agenda",
            "Renew AWS cert", "Follow up on hiring loop",
        ]
        for (i, title) in openTitles.enumerated() {
            try? await career.add(CareerTask(
                id: "task_open_\(i)", title: title, project: "Platform",
                priority: .medium, status: .todo,
                dueDate: world.day(-(i + 1), hour: 18), createdAt: world.day(3, hour: 9)
            ))
        }
        try? await career.add(CareerTask(
            id: "task_overdue_1", title: "Submit expense report", project: "",
            priority: .high, status: .todo, dueDate: world.day(5, hour: 18), createdAt: world.day(10, hour: 9)
        ))
        try? await career.add(CareerTask(
            id: "task_overdue_2", title: "Respond to performance review draft", project: "",
            priority: .urgent, status: .todo, dueDate: world.day(2, hour: 18), createdAt: world.day(9, hour: 9)
        ))

        // 3 projects, one deadline next week.
        try? await career.addProject(CareerProject(
            id: "proj_platform_migration", name: "Platform migration", role: "Lead engineer",
            progressPercent: 70, status: .active, deadline: world.day(-7, hour: 18)
        ))
        try? await career.addProject(CareerProject(
            id: "proj_mobile_v2", name: "Mobile app v2", role: "Contributor",
            progressPercent: 35, status: .active, deadline: world.day(-45, hour: 18)
        ))
        try? await career.addProject(CareerProject(
            id: "proj_onboarding_revamp", name: "Onboarding revamp", role: "Reviewer",
            progressPercent: 100, status: .completed, deadline: world.day(20, hour: 18)
        ))

        // 2 interviews: one past, one upcoming.
        try? await career.addInterview(Interview(
            id: "int_past", company: "Northwind Systems", position: "Senior Engineer",
            status: .rejected, appliedDate: world.day(90, hour: 9)
        ))
        try? await career.addInterview(Interview(
            id: "int_upcoming", company: "Fernhill Labs", position: "Staff Engineer",
            status: .interview, appliedDate: world.day(14, hour: 9)
        ))

        // 4 achievements.
        try? await career.addAchievement(Achievement(
            id: "ach_1", title: "Shipped platform migration phase 1",
            description: "Cut deploy time in half", date: world.day(60, hour: 12), impact: "Deploys down from 40min to 18min"
        ))
        try? await career.addAchievement(Achievement(
            id: "ach_2", title: "Mentored a new hire to full ramp-up",
            date: world.day(45, hour: 12), impact: "Ramped in 6 weeks vs 10 average"
        ))
        try? await career.addAchievement(Achievement(
            id: "ach_3", title: "Led the incident postmortem process revamp",
            date: world.day(30, hour: 12)
        ))
        try? await career.addAchievement(Achievement(
            id: "ach_4", title: "Gave a lightning talk on the new API design",
            date: world.day(15, hour: 12)
        ))

        // 5 network contacts, lastContact 5-70 days ago.
        let networkNames: [(String, String, String, Int)] = [
            ("Priya Shah", "Eng Manager", "Northwind Systems", 5),
            ("Tomas Berg", "Recruiter", "Fernhill Labs", 12),
            ("Elena Kowalski", "Former colleague", "Bright Data Co", 28),
            ("Sam Okafor", "Mentor", "Independent", 45),
            ("Jules Renard", "Conference contact", "DevConf", 70),
        ]
        for (i, contact) in networkNames.enumerated() {
            try? await career.addNetworkContact(NetworkContact(
                id: "netc_\(i)", name: contact.0, role: contact.1, company: contact.2,
                lastContact: world.day(contact.3, hour: 12)
            ))
        }

        // Salary history, 2 entries.
        try? await career.addSalary(SalaryEntry(
            id: "salary_1", amount: 68_000, role: "Software Engineer", company: "Current Co",
            date: world.day(150, hour: 9)
        ))
        try? await career.addSalary(SalaryEntry(
            id: "salary_2", amount: 74_000, role: "Senior Software Engineer", company: "Current Co",
            date: world.day(40, hour: 9)
        ))

        // Skills.
        try? await career.addSkill(CareerSkill(id: "cskill_1", name: "Swift", category: "Engineering", level: 4))
        try? await career.addSkill(CareerSkill(id: "cskill_2", name: "System design", category: "Engineering", level: 3))
        try? await career.addSkill(CareerSkill(id: "cskill_3", name: "Public speaking", category: "Leadership", level: 2))
    }
}

// MARK: - Learning

extension DemoSeed {
    @MainActor
    fileprivate static func seedLearning(
        container: AppContainer, world: DemoWorld, rng: inout SeededGenerator
    ) async {
        let learning = container.learning

        // 3 completed books.
        try? await learning.add(Book(
            id: "book_1", title: "Atomic Habits", author: "James Clear",
            currentPage: 320, totalPages: 320, status: .completed,
            quotes: ["You do not rise to the level of your goals. You fall to the level of your systems."]
        ))
        try? await learning.add(Book(
            id: "book_2", title: "The Pragmatic Programmer", author: "Hunt & Thomas",
            currentPage: 352, totalPages: 352, status: .completed
        ))
        try? await learning.add(Book(
            id: "book_3", title: "Sapiens", author: "Yuval Noah Harari",
            currentPage: 443, totalPages: 443, status: .completed
        ))

        // 2 reading with page progress.
        try? await learning.add(Book(
            id: "book_4", title: "Designing Data-Intensive Applications", author: "Martin Kleppmann",
            currentPage: 210, totalPages: 616, status: .reading
        ))
        try? await learning.add(Book(
            id: "book_5", title: "Four Thousand Weeks", author: "Oliver Burkeman",
            currentPage: 90, totalPages: 288, status: .reading,
            quotes: ["The average human lifespan is absurdly, insultingly brief."]
        ))

        // 3 queued.
        try? await learning.add(Book(id: "book_6", title: "Deep Work", author: "Cal Newport", totalPages: 296, status: .wantToRead))
        try? await learning.add(Book(id: "book_7", title: "The Staff Engineer's Path", author: "Tanya Reilly", totalPages: 350, status: .wantToRead))
        try? await learning.add(Book(id: "book_8", title: "Educated", author: "Tara Westover", totalPages: 334, status: .wantToRead))

        // A few notes/quotes on the currently-reading books.
        try? await learning.addQuote(id: "book_4", quote: "Reliable systems need to be simple to understand.")
        try? await learning.saveNotes(id: "book_4", notes: "Great chapter on replication trade-offs.")

        // 4 skills leveled 2-4.
        try? await learning.addSkill(LearningSkill(id: "lskill_1", name: "Spanish", category: "Language", level: 3, status: .learning))
        try? await learning.addSkill(LearningSkill(id: "lskill_2", name: "Watercolor painting", category: "Art", level: 2, status: .learning))
        try? await learning.addSkill(LearningSkill(id: "lskill_3", name: "Music theory", category: "Music", level: 2, status: .learning))
        try? await learning.addSkill(LearningSkill(id: "lskill_4", name: "Rust", category: "Engineering", level: 4, status: .learning))

        // A language and a course for good measure.
        try? await learning.addLanguage(LanguageStudy(id: "lang_es", name: "Spanish", level: "B1"))
        try? await learning.addCourse(Course(id: "course_1", name: "Distributed Systems", provider: "MIT OCW", progressPercent: 55, status: .active))

        // Queue items.
        try? await learning.addQueueItem(LearningQueueItem(id: "queue_1", title: "Talk: Building reliable systems", kind: .video, createdAt: world.day(20, hour: 12)))
        try? await learning.addQueueItem(LearningQueueItem(id: "queue_2", title: "Podcast: Software at scale", kind: .podcast, createdAt: world.day(10, hour: 12)))
    }
}

// MARK: - Goals

extension DemoSeed {
    @MainActor
    fileprivate static func seedGoals(
        container: AppContainer, world: DemoWorld, rng: inout SeededGenerator
    ) async {
        let goals = container.goals

        try? await goals.add(Goal(
            id: "goal_marathon", title: "Run a half marathon", emoji: "🏃",
            horizon: .quarter, status: .active, progressPercent: 88,
            keyResults: ["Run 3x/week", "Reach 18km long run", "Sub-2h finish"],
            sphereType: .health, why: "Want to prove to myself I can commit to something hard."
        ))
        try? await goals.add(Goal(
            id: "goal_savings", title: "Grow emergency fund to £10k", emoji: "💰",
            horizon: .year, status: .active, progressPercent: 62,
            sphereType: .finance
        ))
        try? await goals.add(Goal(
            id: "goal_spanish", title: "Reach conversational Spanish", emoji: "🗣️",
            horizon: .year, status: .active, progressPercent: 40,
            sphereType: .learning
        ))
        try? await goals.add(Goal(
            id: "goal_promotion", title: "Get promoted to Staff Engineer", emoji: "🚀",
            horizon: .year, status: .active, progressPercent: 95,
            sphereType: .career, why: "Ready for more scope and ownership."
        ))
        try? await goals.add(Goal(
            id: "goal_book", title: "Write a short story collection", emoji: "✍️",
            horizon: .threeYears, status: .active, progressPercent: 8,
            sphereType: .creativity, why: "Always said I would; time to actually start."
        ))

        // 4 habits with reminder weekdays and 180-day completion histories.
        var meditate = Habit(id: "habit_meditate", name: "Meditate daily", emoji: "🧘", identity: "someone who is calm and present", reminderWeekdays: [1, 2, 3, 4, 5, 6, 7])
        var read = Habit(id: "habit_read", name: "Read 30 minutes", emoji: "📚", identity: "a lifelong learner", reminderWeekdays: [1, 2, 3, 4, 5, 6, 7])
        var run = Habit(id: "habit_run", name: "Run 3x/week", emoji: "🏃", identity: "someone who shows up for their body", reminderWeekdays: [2, 4, 6])
        var noSugar = Habit(id: "habit_nosugar", name: "No added sugar", emoji: "🚫🍬", identity: "someone in control of their cravings", reminderWeekdays: [1, 2, 3, 4, 5, 6, 7])

        for daysAgo in stride(from: world.days, through: 0, by: -1) {
            let date = world.day(daysAgo)
            let weekday = Calendar.current.component(.weekday, from: date)
            if rng.chance(0.75) { meditate = meditate.checkingIn(on: date) }
            if rng.chance(0.65) { read = read.checkingIn(on: date) }
            if [2, 4, 6].contains(weekday), rng.chance(0.8) { run = run.checkingIn(on: date) }
            if rng.chance(0.7) { noSugar = noSugar.checkingIn(on: date) }
        }
        try? await goals.addHabit(meditate)
        try? await goals.addHabit(read)
        try? await goals.addHabit(run)
        try? await goals.addHabit(noSugar)
    }
}

// MARK: - Relationships

extension DemoSeed {
    @MainActor
    fileprivate static func seedRelationships(
        container: AppContainer, world: DemoWorld, rng: inout SeededGenerator
    ) async {
        let relationships = container.relationships
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        func birthday(monthsFromNow: Int, day: Int) -> Date {
            let target = calendar.date(byAdding: .month, value: monthsFromNow, to: world.today) ?? world.today
            var comps = calendar.dateComponents([.month, .day], from: target)
            comps.day = day
            comps.year = 1990
            return calendar.date(from: comps) ?? world.today
        }

        // One contact with a birthday within the next week.
        let soonBirthday = calendar.date(byAdding: .day, value: 4, to: world.today) ?? world.today
        var soonComps = calendar.dateComponents([.month, .day], from: soonBirthday)
        soonComps.year = 1991

        let contacts: [(String, String, RelationshipType, DateComponents?, Int)] = [
            ("Alice Turner", "👩", .family, soonComps, 6),
            ("Ben Turner", "👨", .family, calendar.dateComponents([.month, .day], from: birthday(monthsFromNow: 3, day: 14)), 20),
            ("Chloe Whitfield", "👩‍🦰", .friend, calendar.dateComponents([.month, .day], from: birthday(monthsFromNow: 5, day: 2)), 12),
            ("Daniel Osei", "🧑", .friend, calendar.dateComponents([.month, .day], from: birthday(monthsFromNow: -2, day: 22)), 35),
            ("Emma Novak", "👩‍🦱", .colleague, calendar.dateComponents([.month, .day], from: birthday(monthsFromNow: 8, day: 9)), 45),
            ("Farhan Ali", "🧔", .friend, calendar.dateComponents([.month, .day], from: birthday(monthsFromNow: 1, day: 18)), 60),
            ("Grace Lindqvist", "👵", .family, calendar.dateComponents([.month, .day], from: birthday(monthsFromNow: -4, day: 30)), 80),
            ("Harry Sato", "🧑‍🦲", .mentor, calendar.dateComponents([.month, .day], from: birthday(monthsFromNow: 6, day: 11)), 50),
            ("Isla Brennan", "👩‍🎤", .friend, calendar.dateComponents([.month, .day], from: birthday(monthsFromNow: -1, day: 25)), 2),
            ("Jake Bianchi", "🧑‍🍳", .colleague, calendar.dateComponents([.month, .day], from: birthday(monthsFromNow: 9, day: 4)), 55),
            ("Kira Novotna", "👩‍⚕️", .romantic, calendar.dateComponents([.month, .day], from: birthday(monthsFromNow: 2, day: 17)), 3),
        ]
        for (i, contact) in contacts.enumerated() {
            var birthdayDate: Date?
            if var comps = contact.3 {
                comps.year = 1990
                birthdayDate = calendar.date(from: comps)
            }
            try? await relationships.add(Contact(
                id: "contact_\(i)", name: contact.0, emoji: contact.1, type: contact.2,
                birthday: birthdayDate, lastContact: world.day(contact.4, hour: 18),
                reminderDays: contact.2 == .family ? 21 : 30
            ))
        }
    }
}

// MARK: - Hobbies

extension DemoSeed {
    @MainActor
    fileprivate static func seedHobbies(
        container: AppContainer, world: DemoWorld, rng: inout SeededGenerator
    ) async {
        let hobbies = container.hobbies

        let list: [(String, String, String, HobbyFrequency)] = [
            ("hobby_guitar", "Guitar", "🎸", .weekly),
            ("hobby_photography", "Photography", "📷", .weekly),
            ("hobby_chess", "Chess", "♟️", .weekly),
            ("hobby_bouldering", "Bouldering", "🧗", .weekly),
        ]
        for hobby in list {
            try? await hobbies.addHobby(Hobby(
                id: hobby.0, name: hobby.1, emoji: hobby.2, frequency: hobby.3, targetMinutesPerWeek: 120
            ))
        }

        for daysAgo in stride(from: world.days, through: 0, by: -1) {
            let weekday = Calendar.current.component(.weekday, from: world.day(daysAgo))
            if [2, 5].contains(weekday), rng.chance(0.7) {
                try? await hobbies.logSession(HobbySession(
                    id: "hsession_guitar_\(daysAgo)", hobbyId: "hobby_guitar",
                    durationMinutes: Int.random(in: 20...60, using: &rng),
                    date: world.day(daysAgo, hour: 19), rating: Int.random(in: 3...5, using: &rng)
                ))
            }
            if weekday == 7, rng.chance(0.6) {
                try? await hobbies.logSession(HobbySession(
                    id: "hsession_photo_\(daysAgo)", hobbyId: "hobby_photography",
                    durationMinutes: Int.random(in: 30...90, using: &rng),
                    date: world.day(daysAgo, hour: 11), rating: Int.random(in: 3...5, using: &rng)
                ))
            }
            if weekday == 4, rng.chance(0.5) {
                try? await hobbies.logSession(HobbySession(
                    id: "hsession_chess_\(daysAgo)", hobbyId: "hobby_chess",
                    durationMinutes: Int.random(in: 15...45, using: &rng),
                    date: world.day(daysAgo, hour: 20), rating: Int.random(in: 2...5, using: &rng)
                ))
            }
            if [3, 6].contains(weekday), rng.chance(0.55) {
                try? await hobbies.logSession(HobbySession(
                    id: "hsession_boulder_\(daysAgo)", hobbyId: "hobby_bouldering",
                    durationMinutes: Int.random(in: 45...90, using: &rng),
                    date: world.day(daysAgo, hour: 18), rating: Int.random(in: 3...5, using: &rng)
                ))
            }
        }
    }
}

// MARK: - Travel

extension DemoSeed {
    @MainActor
    fileprivate static func seedTravel(
        container: AppContainer, world: DemoWorld, rng: inout SeededGenerator
    ) async {
        let travel = container.travel
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        // Past trip: Barcelona, April, 5 days.
        let barcelonaStart = world.day(90, hour: 8)
        let barcelonaEnd = calendar.date(byAdding: .day, value: 5, to: barcelonaStart) ?? barcelonaStart
        try? await travel.add(TravelPlan(
            id: "trip_barcelona", destination: "Barcelona", country: "Spain", emoji: "🇪🇸",
            type: .city, status: .completed, startDate: barcelonaStart, endDate: barcelonaEnd,
            notes: "Gaudi architecture tour + beach days.", budget: 900, spent: 860
        ))
        try? await travel.initPackingAndDocs(planId: "trip_barcelona")
        for item in ["Passport", "Chargers", "Sunscreen", "Walking shoes", "Swimsuit"] {
            try? await travel.togglePackingItem(planId: "trip_barcelona", item: item)
        }
        for (i, text) in [
            "Landed, the heat is glorious.",
            "Sagrada Familia is unreal in person.",
            "Beach day, way too much sun.",
            "Best tapas of my life tonight.",
            "Heading home, already planning the next one.",
        ].enumerated() {
            try? await travel.addJournalEntry(
                tripId: "trip_barcelona", text: text,
                on: calendar.date(byAdding: .day, value: i, to: barcelonaStart) ?? barcelonaStart
            )
        }

        // Past trip: Kyiv, June.
        let kyivStart = world.day(30, hour: 8)
        let kyivEnd = calendar.date(byAdding: .day, value: 4, to: kyivStart) ?? kyivStart
        try? await travel.add(TravelPlan(
            id: "trip_kyiv", destination: "Kyiv", country: "Ukraine", emoji: "🇺🇦",
            type: .culture, status: .completed, startDate: kyivStart, endDate: kyivEnd,
            notes: "Visiting family friends.", budget: 500, spent: 420
        ))

        // Upcoming trip: Lisbon, Sep 12-15, planning stage.
        var lisbonComps = DateComponents(year: 2026, month: 9, day: 12)
        let lisbonStart = calendar.date(from: lisbonComps) ?? world.today
        lisbonComps.day = 15
        let lisbonEnd = calendar.date(from: lisbonComps) ?? world.today
        try? await travel.add(TravelPlan(
            id: "trip_lisbon", destination: "Lisbon", country: "Portugal", emoji: "🇵🇹",
            type: .city, status: .booked, startDate: lisbonStart, endDate: lisbonEnd,
            notes: "Long weekend, want to see Belem and Sintra.", budget: 700
        ))
        try? await travel.initPackingAndDocs(planId: "trip_lisbon")
        for item in ["Passport", "Chargers"] {
            try? await travel.togglePackingItem(planId: "trip_lisbon", item: item)
        }

        // Visited countries.
        try? await travel.addVisited(VisitedCountry(name: "Spain", flag: "🇪🇸", year: 2026))
        try? await travel.addVisited(VisitedCountry(name: "Ukraine", flag: "🇺🇦", year: 2026))
        try? await travel.addVisited(VisitedCountry(name: "France", flag: "🇫🇷", year: 2022))
        try? await travel.addVisited(VisitedCountry(name: "Italy", flag: "🇮🇹", year: 2019))

        // Wishlist.
        try? await travel.addWishlist(WishlistDestination(id: "wish_tokyo", destination: "Tokyo", country: "Japan", flag: "🇯🇵"))
        try? await travel.addWishlist(WishlistDestination(id: "wish_reykjavik", destination: "Reykjavik", country: "Iceland", flag: "🇮🇸"))
        try? await travel.addWishlist(WishlistDestination(id: "wish_rome", destination: "Rome", country: "Italy", flag: "🇮🇹"))
    }
}

// MARK: - Creativity

extension DemoSeed {
    @MainActor
    fileprivate static func seedCreativity(
        container: AppContainer, world: DemoWorld, rng: inout SeededGenerator
    ) async {
        let creativity = container.creativity

        try? await creativity.add(CreativeProject(
            id: "creative_song", title: "Song demo — 'Long Way Home'", type: .music,
            status: .inProgress, progressPercent: 60, createdAt: world.day(80, hour: 12)
        ))
        try? await creativity.add(CreativeProject(
            id: "creative_blog", title: "Personal blog rewrite", type: .writing,
            status: .inProgress, progressPercent: 35, createdAt: world.day(50, hour: 12)
        ))
        try? await creativity.add(CreativeProject(
            id: "creative_watercolors", title: "Watercolor sketchbook", type: .drawing,
            status: .inProgress, progressPercent: 20, createdAt: world.day(30, hour: 12)
        ))

        for daysAgo in stride(from: world.days, through: 0, by: -4) {
            guard rng.chance(0.4) else { continue }
            let projectId = rng.pick(["creative_song", "creative_blog", "creative_watercolors"])
            try? await creativity.logSession(
                projectId: projectId, minutes: Int.random(in: 20...90, using: &rng), on: world.day(daysAgo, hour: 20)
            )
        }

        let ideas = [
            "Cover song idea: slow acoustic version of an 80s hit.",
            "Blog post: what shipping fast actually costs you long-term.",
            "Watercolor: the view from the kitchen window at sunset.",
            "Short story about a lighthouse keeper who never sees the sea.",
            "Photo series: London at 6am before the city wakes up.",
            "Blog post: a year of habit tracking, what actually stuck.",
            "Song idea: a bridge that changes key entirely.",
            "Watercolor series: every mug in the flat.",
            "Blog post: notes from six months of demo data (meta).",
            "Idea: turn the guitar practice log into a public streak page.",
        ]
        for (i, idea) in ideas.enumerated() {
            try? await creativity.addIdea(idea, on: world.day(world.days - i * 15, hour: 21))
        }
    }
}

// MARK: - Home sphere

extension DemoSeed {
    @MainActor
    fileprivate static func seedHomeSphere(
        container: AppContainer, world: DemoWorld, rng: inout SeededGenerator
    ) async {
        let home = container.homeSphere

        // 6 chores, some recurring weekly, 2 due now.
        try? await home.add(HomeTask(
            id: "chore_vacuum", title: "Vacuum the flat", category: .cleaning,
            dueDate: world.day(-1, hour: 18), isRecurring: true, recurrenceDays: 7, createdAt: world.day(60, hour: 9)
        ))
        try? await home.add(HomeTask(
            id: "chore_laundry", title: "Do laundry", category: .cleaning,
            dueDate: world.day(0, hour: 18), isRecurring: true, recurrenceDays: 7, createdAt: world.day(60, hour: 9)
        ))
        try? await home.add(HomeTask(
            id: "chore_bins", title: "Take out the bins", category: .cleaning,
            dueDate: world.day(0, hour: 18), isRecurring: true, recurrenceDays: 7, createdAt: world.day(60, hour: 9)
        ))
        try? await home.add(HomeTask(
            id: "chore_fixtap", title: "Fix the leaking kitchen tap", category: .repair,
            dueDate: world.day(-3, hour: 18), isRecurring: false, createdAt: world.day(10, hour: 9)
        ))
        try? await home.add(HomeTask(
            id: "chore_declutter", title: "Declutter the hallway cupboard", category: .organization,
            dueDate: world.day(-10, hour: 18), isRecurring: false, createdAt: world.day(20, hour: 9)
        ))
        try? await home.add(HomeTask(
            id: "chore_bills", title: "Review household bills", category: .bills,
            dueDate: world.day(2, hour: 18), isRecurring: true, recurrenceDays: 30, createdAt: world.day(60, hour: 9)
        ))

        // 3 plants.
        try? await home.addPlant(Plant(id: "plant_monstera", name: "Monstera", emoji: "🪴", lastWatered: world.day(2, hour: 9), intervalDays: 7))
        try? await home.addPlant(Plant(id: "plant_basil", name: "Basil", emoji: "🌿", lastWatered: world.day(9, hour: 9), intervalDays: 3))
        try? await home.addPlant(Plant(id: "plant_cactus", name: "Cactus", emoji: "🌵", lastWatered: world.day(14, hour: 9), intervalDays: 21))

        // Shopping list: 6 unchecked, 4 checked.
        let unchecked = ["Milk", "Eggs", "Coffee beans", "Dish soap", "Bin bags", "Olive oil"]
        let checked = ["Bread", "Bananas", "Toothpaste", "Kitchen roll"]
        for item in unchecked {
            try? await home.addShoppingItem(ShoppingItem(id: "shop_\(item)", name: item, category: "Groceries"))
        }
        for item in checked {
            let id = "shop_\(item)"
            try? await home.addShoppingItem(ShoppingItem(id: id, name: item, category: "Groceries"))
            try? await home.toggleShoppingItem(id: id)
        }
    }
}
#endif

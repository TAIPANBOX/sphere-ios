import Foundation
import GRDB
import Observation

struct NudgeLogEntry: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "nudge_log"
    var id: String
    var firedAt: Date
}

/// Assembles the nudge context from the stores, applies the cooldown ledger,
/// and exposes the one proactive nudge (if any) to surface today.
@MainActor
@Observable
public final class NudgeStore {
    public private(set) var activeNudge: Nudge?

    private let database: AppDatabase
    private let mindfulness: MindfulnessStore
    private let finance: FinanceStore
    private let career: CareerStore
    private let homeSphere: HomeSphereStore
    private let rest: RestStore

    private var lastFired: [String: Date] = [:]

    public init(
        database: AppDatabase,
        mindfulness: MindfulnessStore,
        finance: FinanceStore,
        career: CareerStore,
        homeSphere: HomeSphereStore,
        rest: RestStore
    ) {
        self.database = database
        self.mindfulness = mindfulness
        self.finance = finance
        self.career = career
        self.homeSphere = homeSphere
        self.rest = rest
    }

    public func loadLedger() async throws {
        let entries = try await database.writer.read { db in try NudgeLogEntry.fetchAll(db) }
        lastFired = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.firedAt) })
    }

    /// Recomputes which nudge (if any) to show. Does not record it — call
    /// `acknowledge` when the user sees/acts on it so the cooldown starts.
    public func refresh(now: Date = Date()) {
        let candidates = NudgeEngine.evaluate(buildContext(now: now))
        activeNudge = NudgeScheduler.select(candidates: candidates, lastFired: lastFired, now: now)
    }

    /// Records the nudge as fired (starts its cooldown + the daily cap) and
    /// clears it from view.
    public func acknowledge(_ nudge: Nudge, now: Date = Date()) async {
        lastFired[nudge.id] = now
        let entry = NudgeLogEntry(id: nudge.id, firedAt: now)
        try? await database.writer.write { db in try entry.save(db) }
        if activeNudge?.id == nudge.id { activeNudge = nil }
    }

    func buildContext(now: Date = Date()) -> NudgeContext {
        let calendar = DayKey.calendar
        let stale = career.staleContacts(asOf: now).first
        let plant = mostOverduePlant(now: now)
        return NudgeContext(
            now: now,
            hour: calendar.component(.hour, from: now),
            recentStress: Array(mindfulness.last7Stress(asOf: now).suffix(3)),
            meditatedToday: mindfulness.hasMeditated(on: now),
            meditationStreak: mindfulness.currentStreak(asOf: now),
            monthlyBudgetTotal: finance.monthlyBudgetTotal,
            spentThisMonth: finance.spentThisMonthTotal(asOf: now),
            dayOfMonth: calendar.component(.day, from: now),
            staleContact: stale.map { ($0.name, $0.daysSinceContact(asOf: now)) },
            thirstyPlant: plant,
            sleepDebtHours: rest.sleepDebtLast7(asOf: now)
        )
    }

    private func mostOverduePlant(now: Date) -> (name: String, daysOverdue: Int)? {
        let calendar = DayKey.calendar
        let overdue = homeSphere.plants.compactMap { plant -> (String, Int)? in
            guard let last = plant.lastWatered else { return (plant.name, plant.intervalDays) }
            let daysSince = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)
            ).day ?? 0
            let over = daysSince - plant.intervalDays
            return over > 0 ? (plant.name, over) : nil
        }
        return overdue.max { $0.1 < $1.1 }.map { (name: $0.0, daysOverdue: $0.1) }
    }
}

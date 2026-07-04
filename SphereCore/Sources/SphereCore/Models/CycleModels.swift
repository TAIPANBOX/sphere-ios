import Foundation
import GRDB

/// Menstrual flow intensity for a logged period day.
public enum FlowLevel: String, Codable, CaseIterable, Sendable {
    case light, medium, heavy

    public var label: String {
        switch self {
        case .light: "Light"
        case .medium: "Medium"
        case .heavy: "Heavy"
        }
    }

    public var emoji: String {
        switch self {
        case .light: "💧"
        case .medium: "🩸"
        case .heavy: "🔴"
        }
    }
}

/// Common cycle-related symptoms, stored as raw strings on the entry so the
/// set can grow without a migration.
public enum CycleSymptom: String, Codable, CaseIterable, Sendable {
    case cramps, headache, bloating, fatigue, moodSwings, acne, cravings, backPain

    public var label: String {
        switch self {
        case .cramps: "Cramps"
        case .headache: "Headache"
        case .bloating: "Bloating"
        case .fatigue: "Fatigue"
        case .moodSwings: "Mood swings"
        case .acne: "Acne"
        case .cravings: "Cravings"
        case .backPain: "Back pain"
        }
    }
}

/// One logged menstruation (period), keyed by its start day. `endDate` nil
/// means the period is still ongoing. Cycle predictions are derived from the
/// gaps between successive `startDate`s — see `CyclePredictor`.
public struct CycleEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var startDate: Date
    public var endDate: Date?
    public var flow: FlowLevel
    /// `CycleSymptom` raw values.
    public var symptoms: [String]
    public var note: String

    public init(
        id: String,
        startDate: Date,
        endDate: Date? = nil,
        flow: FlowLevel = .medium,
        symptoms: [String] = [],
        note: String = ""
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.flow = flow
        self.symptoms = symptoms
        self.note = note
    }

    public var startKey: String { DayKey.make(startDate) }

    /// Duration in days (inclusive) once the period has ended.
    public var periodLengthDays: Int? {
        guard let endDate else { return nil }
        let days = DayKey.calendar.dateComponents(
            [.day], from: DayKey.calendar.startOfDay(for: startDate),
            to: DayKey.calendar.startOfDay(for: endDate)
        ).day ?? 0
        return max(days + 1, 1)
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("cycle", now: now)
    }
}

extension CycleEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "cycle_entries"
}

/// Where the user is in her cycle right now.
public enum CyclePhase: String, Sendable {
    case menstrual, follicular, ovulation, luteal

    public var label: String {
        switch self {
        case .menstrual: "Menstrual"
        case .follicular: "Follicular"
        case .ovulation: "Ovulation"
        case .luteal: "Luteal"
        }
    }

    public var emoji: String {
        switch self {
        case .menstrual: "🩸"
        case .follicular: "🌱"
        case .ovulation: "🥚"
        case .luteal: "🌙"
        }
    }
}

/// Result of projecting the next cycle from logged history.
public struct CyclePrediction: Sendable, Equatable {
    public let currentCycleDay: Int
    public let averageCycleLength: Int
    public let averagePeriodLength: Int
    public let phase: CyclePhase
    public let isOnPeriod: Bool
    public let nextPeriodStart: Date
    public let daysUntilNextPeriod: Int
    public let ovulationDate: Date
    public let fertileWindow: ClosedRange<Date>
    /// True when only the default cycle length could be assumed (fewer than
    /// two logged periods), so predictions are rough.
    public let isEstimate: Bool
}

/// Pure, testable cycle math. No calendar assumptions beyond the Gregorian,
/// time-zone-pinned `DayKey.calendar` used everywhere else.
public enum CyclePredictor {
    public static let defaultCycleLength = 28
    public static let defaultPeriodLength = 5
    /// Ovulation occurs ~14 days before the next period (luteal phase length).
    public static let lutealPhaseLength = 14

    /// Mean gap (in days) between the most recent successive period starts,
    /// clamped to a physiologically plausible range. Uses up to the last six
    /// cycles so recent regularity dominates.
    public static func averageCycleLength(_ entries: [CycleEntry]) -> Int {
        let starts = entries.map(\.startDate).sorted()
        guard starts.count >= 2 else { return defaultCycleLength }
        let recent = starts.suffix(7) // up to 6 gaps
        var gaps: [Int] = []
        for pair in zip(recent, recent.dropFirst()) {
            let days = DayKey.calendar.dateComponents(
                [.day], from: DayKey.calendar.startOfDay(for: pair.0),
                to: DayKey.calendar.startOfDay(for: pair.1)
            ).day ?? 0
            if days > 0 { gaps.append(days) }
        }
        guard !gaps.isEmpty else { return defaultCycleLength }
        let mean = Int((Double(gaps.reduce(0, +)) / Double(gaps.count)).rounded())
        return min(max(mean, 21), 45)
    }

    public static func averagePeriodLength(_ entries: [CycleEntry]) -> Int {
        let lengths = entries.compactMap(\.periodLengthDays)
        guard !lengths.isEmpty else { return defaultPeriodLength }
        return Int((Double(lengths.reduce(0, +)) / Double(lengths.count)).rounded())
    }

    /// Projects the current phase and upcoming dates from logged history.
    /// Returns nil when nothing has been logged yet.
    public static func predict(_ entries: [CycleEntry], asOf now: Date = Date()) -> CyclePrediction? {
        let calendar = DayKey.calendar
        let today = calendar.startOfDay(for: now)
        guard let last = entries.max(by: { $0.startDate < $1.startDate }) else { return nil }
        let lastStart = calendar.startOfDay(for: last.startDate)

        let cycleLength = averageCycleLength(entries)
        let periodLength = averagePeriodLength(entries)
        let isEstimate = entries.count < 2

        let dayIndex = calendar.dateComponents([.day], from: lastStart, to: today).day ?? 0
        let currentCycleDay = max(dayIndex + 1, 1)

        let nextStart = calendar.date(byAdding: .day, value: cycleLength, to: lastStart) ?? lastStart
        let daysUntilNext = calendar.dateComponents([.day], from: today, to: nextStart).day ?? 0
        let ovulation = calendar.date(byAdding: .day, value: -lutealPhaseLength, to: nextStart) ?? nextStart
        let fertileStart = calendar.date(byAdding: .day, value: -5, to: ovulation) ?? ovulation
        let fertileEnd = calendar.date(byAdding: .day, value: 1, to: ovulation) ?? ovulation

        // On period if within an explicit end date, or within the average
        // period length of the last start when still open.
        let onPeriod: Bool
        if let end = last.endDate {
            onPeriod = today >= lastStart && today <= calendar.startOfDay(for: end)
        } else {
            onPeriod = dayIndex >= 0 && dayIndex < periodLength
        }

        let phase: CyclePhase
        if onPeriod {
            phase = .menstrual
        } else if today >= calendar.startOfDay(for: fertileStart)
            && today <= calendar.startOfDay(for: fertileEnd) {
            phase = .ovulation
        } else if today < calendar.startOfDay(for: ovulation) {
            phase = .follicular
        } else {
            phase = .luteal
        }

        return CyclePrediction(
            currentCycleDay: currentCycleDay,
            averageCycleLength: cycleLength,
            averagePeriodLength: periodLength,
            phase: phase,
            isOnPeriod: onPeriod,
            nextPeriodStart: nextStart,
            daysUntilNextPeriod: daysUntilNext,
            ovulationDate: ovulation,
            fertileWindow: min(fertileStart, fertileEnd)...max(fertileStart, fertileEnd),
            isEstimate: isEstimate
        )
    }
}

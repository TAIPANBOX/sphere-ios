import Foundation
import GRDB

public enum MeditationType: String, Codable, CaseIterable, Sendable {
    case breathing, bodyScan, visualization, lovingKindness, focus, sleep, custom

    public var label: String {
        switch self {
        case .breathing: "Breathing"
        case .bodyScan: "Body Scan"
        case .visualization: "Visualization"
        case .lovingKindness: "Loving Kindness"
        case .focus: "Focus"
        case .sleep: "Sleep"
        case .custom: "Custom"
        }
    }

    public var emoji: String {
        switch self {
        case .breathing: "🌬️"
        case .bodyScan: "🧘"
        case .visualization: "🌅"
        case .lovingKindness: "💛"
        case .focus: "🎯"
        case .sleep: "🌙"
        case .custom: "✨"
        }
    }
}

public struct MeditationSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var type: MeditationType
    public var durationMinutes: Int
    public var date: Date
    public var note: String
    /// 1–5
    public var moodBefore: Int
    /// 1–5
    public var moodAfter: Int

    public init(
        id: String,
        type: MeditationType = .breathing,
        durationMinutes: Int,
        date: Date,
        note: String = "",
        moodBefore: Int = 3,
        moodAfter: Int = 4
    ) {
        self.id = id
        self.type = type
        self.durationMinutes = durationMinutes
        self.date = date
        self.note = note
        self.moodBefore = moodBefore
        self.moodAfter = moodAfter
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("med", now: now)
    }
}

extension MeditationSession: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "meditation_sessions"
}

public struct JournalEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var date: Date
    public var text: String
    public var sentiment: Double?

    public init(id: String, date: Date, text: String, sentiment: Double? = nil) {
        self.id = id
        self.date = date
        self.text = text
        self.sentiment = sentiment
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("journal", now: now)
    }
}

extension JournalEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "journal_entries"
}

/// One gratitude note (1–3 short lines the user is grateful for). The most
/// evidence-backed wellbeing practice; absent in the Flutter app.
public struct GratitudeEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var date: Date
    public var content: String

    public init(id: String, date: Date, content: String) {
        self.id = id
        self.date = date
        self.content = content
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("gratitude", now: now)
    }
}

extension GratitudeEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "gratitude_entries"
}

/// A daily affirmation. Seeded ones ship with the app; users can add their
/// own (isCustom = true).
public struct Affirmation: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var isCustom: Bool

    public init(id: String, text: String, isCustom: Bool = true) {
        self.id = id
        self.text = text
        self.isCustom = isCustom
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("affirmation", now: now)
    }

    /// Built-in affirmations shown when the user hasn't added their own.
    public static let seeds: [String] = [
        "I am doing my best, and that is enough.",
        "I can handle whatever today brings.",
        "Small steps still move me forward.",
        "I deserve rest as much as effort.",
        "I choose calm over worry.",
        "My feelings are valid, and they will pass.",
        "I am growing, even when it's hard to see.",
        "I am grateful for what I have right now.",
        "Progress, not perfection.",
        "I am exactly where I need to be today.",
    ]

    /// A stable pick for the given day, so the affirmation stays constant
    /// through the day and rotates daily.
    public static func daily(for date: Date = Date(), custom: [Affirmation] = []) -> String {
        let pool = custom.isEmpty ? seeds : custom.map(\.text)
        guard !pool.isEmpty else { return seeds[0] }
        let day = DayKey.calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return pool[day % pool.count]
    }
}

extension Affirmation: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "affirmations"
}

// MARK: - Focus & discipline (Tysh-inspired)

/// Daily "discipline score" (0–100) from positive, self-logged actions —
/// focus time, a meditation, and focus consistency. Deliberately built from
/// what you *did*, not surveillance of what you avoided.
public enum DisciplineScore {
    public static let focusGoalMinutes = 60

    public static func compute(
        focusMinutesToday: Int,
        meditatedToday: Bool,
        focusStreakDays: Int,
        focusGoalMinutes: Int = focusGoalMinutes
    ) -> Int {
        let focusPart = min(Double(focusMinutesToday) / Double(max(focusGoalMinutes, 1)), 1) * 50
        let meditationPart = meditatedToday ? 25.0 : 0
        let streakPart = min(Double(focusStreakDays) / 7.0, 1) * 25
        return Int((focusPart + meditationPart + streakPart).rounded())
    }
}

/// Guided breathing cadences (seconds per phase). 4-7-8 to wind down, box for
/// steady calm, coherent for balance.
public enum BreathingPattern: String, CaseIterable, Sendable, Identifiable {
    case fourSevenEight
    case box
    case coherent

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fourSevenEight: "4-7-8"
        case .box: "Box 4-4-4-4"
        case .coherent: "Coherent 5-5"
        }
    }

    public var subtitle: String {
        switch self {
        case .fourSevenEight: "Wind down before sleep"
        case .box: "Steady, focused calm"
        case .coherent: "Balance in ~5 minutes"
        }
    }

    /// Seconds for inhale, hold-in, exhale, hold-out (0 = skip that phase).
    public var timing: (inhale: Int, holdIn: Int, exhale: Int, holdOut: Int) {
        switch self {
        case .fourSevenEight: (4, 7, 8, 0)
        case .box: (4, 4, 4, 4)
        case .coherent: (5, 0, 5, 0)
        }
    }
}

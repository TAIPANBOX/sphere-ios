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
        "med_\(Int64(now.timeIntervalSince1970 * 1000))"
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
        "journal_\(Int64(now.timeIntervalSince1970 * 1000))"
    }
}

extension JournalEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "journal_entries"
}

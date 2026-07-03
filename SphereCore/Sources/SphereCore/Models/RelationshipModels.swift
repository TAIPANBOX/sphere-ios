import Foundation
import GRDB

public enum RelationshipType: String, Codable, CaseIterable, Sendable {
    case family, friend, colleague, romantic, mentor, other

    public var label: String {
        switch self {
        case .family: "Family"
        case .friend: "Friend"
        case .colleague: "Colleague"
        case .romantic: "Partner"
        case .mentor: "Mentor"
        case .other: "Other"
        }
    }

    public var emoji: String {
        switch self {
        case .family: "👨‍👩‍👧"
        case .friend: "🤝"
        case .colleague: "💼"
        case .romantic: "❤️"
        case .mentor: "🎓"
        case .other: "👤"
        }
    }
}

public struct Contact: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    public var type: RelationshipType
    public var birthday: Date?
    public var lastContact: Date?
    public var note: String
    /// Nudge to reach out after this many days of silence.
    public var reminderDays: Int
    public var giftIdeas: [String]
    public var meetingNotes: [String]
    public var sharedExperiences: [String]
    public var importantInfo: String

    public init(
        id: String,
        name: String,
        emoji: String = "👤",
        type: RelationshipType = .friend,
        birthday: Date? = nil,
        lastContact: Date? = nil,
        note: String = "",
        reminderDays: Int = 30,
        giftIdeas: [String] = [],
        meetingNotes: [String] = [],
        sharedExperiences: [String] = [],
        importantInfo: String = ""
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.type = type
        self.birthday = birthday
        self.lastContact = lastContact
        self.note = note
        self.reminderDays = reminderDays
        self.giftIdeas = giftIdeas
        self.meetingNotes = meetingNotes
        self.sharedExperiences = sharedExperiences
        self.importantInfo = importantInfo
    }

    public static func newID(now: Date = Date()) -> String {
        "contact_\(Int64(now.timeIntervalSince1970 * 1000))"
    }

    /// Days until the next occurrence of the birthday (rolls to next year).
    public func daysUntilBirthday(asOf now: Date = Date()) -> Int? {
        guard let birthday else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let birthdayParts = calendar.dateComponents([.month, .day], from: birthday)
        var next = calendar.nextDate(
            after: today.addingTimeInterval(-1),
            matching: birthdayParts,
            matchingPolicy: .nextTime
        )
        if next == nil {
            var parts = calendar.dateComponents([.year], from: today)
            parts.month = birthdayParts.month
            parts.day = birthdayParts.day
            next = calendar.date(from: parts)
        }
        guard let next else { return nil }
        return calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: next)).day
    }

    public func hasBirthdayThisMonth(asOf now: Date = Date()) -> Bool {
        guard let birthday else { return false }
        return Calendar.current.component(.month, from: birthday)
            == Calendar.current.component(.month, from: now)
    }

    public func needsCheckin(asOf now: Date = Date()) -> Bool {
        guard let lastContact else { return true }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: lastContact),
            to: Calendar.current.startOfDay(for: now)
        ).day ?? 0
        return days >= reminderDays
    }
}

extension Contact: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "contacts"
}

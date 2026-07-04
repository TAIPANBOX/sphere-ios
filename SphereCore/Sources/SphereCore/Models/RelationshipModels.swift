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
        EntityID.make("contact", now: now)
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

// MARK: - relationships-v2 (custom dates, message templates, meeting prep)

/// A date tied to a contact beyond their birthday — an anniversary, a "met
/// on" date, a kid's birthday, etc.
public struct CustomDate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var contactId: String
    public var label: String
    public var date: Date
    public var recursYearly: Bool

    public init(id: String, contactId: String, label: String, date: Date, recursYearly: Bool = true) {
        self.id = id
        self.contactId = contactId
        self.label = label
        self.date = date
        self.recursYearly = recursYearly
    }

    /// Days until the next occurrence (rolls to next year when recurring),
    /// or nil for a one-off date already in the past.
    public func daysUntil(asOf now: Date = Date()) -> Int? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        if recursYearly {
            let parts = calendar.dateComponents([.month, .day], from: date)
            guard let next = calendar.nextDate(
                after: today.addingTimeInterval(-1), matching: parts, matchingPolicy: .nextTime
            ) else { return nil }
            return calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: next)).day
        } else {
            let target = calendar.startOfDay(for: date)
            guard target >= today else { return nil }
            return calendar.dateComponents([.day], from: today, to: target).day
        }
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("customdate", now: now) }
}

extension CustomDate: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "custom_dates"
}

/// A reusable message the user can copy when reaching out.
public struct MessageTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var body: String

    public init(id: String, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("template", now: now) }

    /// Built-in templates offered when the user hasn't made their own.
    public static let seeds: [MessageTemplate] = [
        MessageTemplate(id: "seed_bday", title: "Happy birthday",
                        body: "Happy birthday! 🎉 Hope you have a wonderful day."),
        MessageTemplate(id: "seed_catchup", title: "Long time no see",
                        body: "Hey! It's been a while — would love to catch up soon. How are you?"),
        MessageTemplate(id: "seed_thinking", title: "Thinking of you",
                        body: "Just thinking of you and wanted to say hi. Hope all is well!"),
    ]
}

extension MessageTemplate: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "message_templates"
}

/// Assembles the glanceable "prep card" shown before you see someone — the
/// stored facts a personal CRM surfaces so you never walk in cold. Pure data
/// (an agent can enrich it later from Engram recall).
public enum MeetingPrep {
    public static func facts(
        for contact: Contact, customDates: [CustomDate] = [], asOf now: Date = Date()
    ) -> [String] {
        var lines: [String] = []
        let calendar = Calendar.current

        if let last = contact.lastContact {
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)
            ).day ?? 0
            lines.append(days == 0 ? "Last talked today" : "Last talked \(days) day\(days == 1 ? "" : "s") ago")
        } else {
            lines.append("No chats logged yet")
        }

        if let days = contact.daysUntilBirthday(asOf: now), days <= 30 {
            lines.append(days == 0 ? "Birthday today 🎂" : "Birthday in \(days) day\(days == 1 ? "" : "s")")
        }

        for custom in customDates where custom.contactId == contact.id {
            if let days = custom.daysUntil(asOf: now), days <= 30 {
                lines.append("\(custom.label) in \(days) day\(days == 1 ? "" : "s")")
            }
        }

        if !contact.importantInfo.isEmpty { lines.append(contact.importantInfo) }
        if let lastNote = contact.meetingNotes.last { lines.append("Last note: \(lastNote)") }
        if !contact.giftIdeas.isEmpty {
            lines.append("Gift ideas: \(contact.giftIdeas.joined(separator: ", "))")
        }
        return lines
    }
}

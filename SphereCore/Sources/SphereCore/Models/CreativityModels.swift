import Foundation
import GRDB

public enum CreativeType: String, Codable, CaseIterable, Sendable {
    case writing, drawing, music, photography, video, design, coding, other

    public var label: String {
        switch self {
        case .writing: "Writing"
        case .drawing: "Drawing"
        case .music: "Music"
        case .photography: "Photography"
        case .video: "Video"
        case .design: "Design"
        case .coding: "Coding"
        case .other: "Other"
        }
    }

    public var emoji: String {
        switch self {
        case .writing: "✍️"
        case .drawing: "🎨"
        case .music: "🎵"
        case .photography: "📷"
        case .video: "🎬"
        case .design: "💻"
        case .coding: "👨‍💻"
        case .other: "✨"
        }
    }
}

/// The Dart enum is `ProjectStatus` too, but that name is taken by the
/// career sphere here.
public enum CreativeProjectStatus: String, Codable, CaseIterable, Sendable {
    case idea, inProgress, paused, completed
}

public struct CreativeProject: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var description: String
    public var type: CreativeType
    public var status: CreativeProjectStatus
    /// 0–100
    public var progressPercent: Int
    public var createdAt: Date
    public var lastWorkedOn: Date?
    public var collaborators: [String]

    public init(
        id: String,
        title: String,
        description: String = "",
        type: CreativeType = .other,
        status: CreativeProjectStatus = .inProgress,
        progressPercent: Int = 0,
        createdAt: Date,
        lastWorkedOn: Date? = nil,
        collaborators: [String] = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.type = type
        self.status = status
        self.progressPercent = progressPercent
        self.createdAt = createdAt
        self.lastWorkedOn = lastWorkedOn
        self.collaborators = collaborators
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("creative", now: now)
    }
}

extension CreativeProject: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "creative_projects"
}

public struct InspirationItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var content: String
    public var tag: String
    public var date: Date

    public init(id: String, content: String, tag: String = "Idea", date: Date) {
        self.id = id
        self.content = content
        self.tag = tag
        self.date = date
    }

    public static func newID(now: Date = Date()) -> String {
        EntityID.make("insp", now: now)
    }
}

extension InspirationItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "inspirations"
}

import Foundation
import GRDB

/// A photo attached to a trip. The image bytes live in a file (App Group); this
/// row just points at it by filename.
public struct TripPhoto: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var planId: String
    public var filename: String
    public var caption: String
    public var createdAt: Date

    public init(
        id: String, planId: String, filename: String,
        caption: String = "", createdAt: Date
    ) {
        self.id = id
        self.planId = planId
        self.filename = filename
        self.caption = caption
        self.createdAt = createdAt
    }

    public static func newID(now: Date = Date()) -> String { EntityID.make("tripphoto", now: now) }
}

extension TripPhoto: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "trip_photos"
}

/// Persists trip photo image data outside the database (downscaled JPEGs in the
/// App Group). Behind a protocol so SphereCore stays UIKit-free and the store
/// is testable.
public protocol TripPhotoStoring: Sendable {
    /// Saves image data, returning the stored filename (nil on failure).
    func save(_ data: Data) -> String?
    func fileURL(for filename: String) -> URL?
    func delete(_ filename: String)
}

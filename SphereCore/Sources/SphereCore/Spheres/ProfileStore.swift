import Foundation
import GRDB
import Observation

/// The user profile — shared context for every agent. Persisted as a single
/// JSON row (`id == "main"`) in ``AppDatabase``.
@MainActor
@Observable
public final class ProfileStore {
    public private(set) var profile = UserProfile()

    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func load() async throws {
        let json = try await database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT data FROM user_profile WHERE id = 'main'")
        }
        if let json, let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = decoded
        }
    }

    /// Replaces the whole profile and persists it.
    public func save(_ profile: UserProfile) async throws {
        self.profile = profile
        let json = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO user_profile (id, data) VALUES ('main', ?)
                    ON CONFLICT(id) DO UPDATE SET data = excluded.data
                    """,
                arguments: [json]
            )
        }
    }

    /// Mutates the current profile in place and persists it.
    public func update(_ mutate: (inout UserProfile) -> Void) async throws {
        var copy = profile
        mutate(&copy)
        try await save(copy)
    }

    public func setSphereActive(_ sphere: SphereType, active: Bool) async throws {
        try await update { profile in
            // Empty list means "all active"; the first toggle-off must
            // therefore materialize the full set minus the disabled sphere.
            var enabled = profile.activeSpheres.isEmpty
                ? Set(SphereType.allCases.map(\.rawValue))
                : Set(profile.activeSpheres)
            if active { enabled.insert(sphere.rawValue) } else { enabled.remove(sphere.rawValue) }
            profile.activeSpheres = enabled.count == SphereType.allCases.count
                ? []
                : SphereType.allCases.map(\.rawValue).filter(enabled.contains)
        }
    }

    /// Persists a new sphere order (the full active-sphere sequence after a
    /// drag-to-reorder).
    public func setSphereOrder(_ spheres: [SphereType]) async throws {
        try await update { $0.sphereOrder = spheres.map(\.rawValue) }
    }

    /// Context string for agent system prompts (see ``UserProfile/agentContext(asOf:)``).
    public var agentContext: String {
        profile.agentContext()
    }
}

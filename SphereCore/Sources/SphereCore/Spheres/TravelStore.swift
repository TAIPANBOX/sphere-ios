import Foundation
import GRDB
import Observation

/// Travel sphere store: trip planner with packing/document checklists,
/// countries visited, and the dream list. Follows the golden-template shape
/// (docs/HANDOFF.md).
@MainActor
@Observable
public final class TravelStore {
    public private(set) var plans: [TravelPlan] = []
    public private(set) var visited: [VisitedCountry] = []
    public private(set) var wishlist: [WishlistDestination] = []

    private let database: AppDatabase
    private let engram: EngramStore?

    public init(database: AppDatabase, engram: EngramStore? = nil) {
        self.database = database
        self.engram = engram
    }

    public func load() async throws {
        let (plans, visited, wishlist) = try await database.writer.read { db in
            (
                try TravelPlan.fetchAll(db),
                try VisitedCountry.fetchAll(db),
                try WishlistDestination.fetchAll(db)
            )
        }
        self.plans = plans
        self.visited = visited
        self.wishlist = wishlist
    }

    // MARK: - Trips

    public func add(_ plan: TravelPlan) async throws {
        try await database.writer.write { db in try plan.insert(db) }
        plans.append(plan)
        engram?.note(
            agentId: SphereType.travel.rawValue,
            content: "Planning a \(plan.type.rawValue) trip to \(plan.destination)"
                + (plan.country.isEmpty ? "" : ", \(plan.country)"),
            tags: ["log", "travel", "trip"]
        )
    }

    public func update(_ plan: TravelPlan) async throws {
        try await database.writer.write { db in try plan.save(db) }
        plans = plans.map { $0.id == plan.id ? plan : $0 }
    }

    public func remove(id: String) async throws {
        _ = try await database.writer.write { db in try TravelPlan.deleteOne(db, key: id) }
        plans.removeAll { $0.id == id }
    }

    /// The soonest booked trip with a known countdown.
    public func nextTrip(asOf now: Date = Date()) -> TravelPlan? {
        plans
            .filter { $0.status == .booked && $0.daysUntil(asOf: now) != nil }
            .min { ($0.daysUntil(asOf: now) ?? 999) < ($1.daysUntil(asOf: now) ?? 999) }
    }

    // MARK: - Checklists

    public func togglePackingItem(planId: String, item: String) async throws {
        guard var plan = plans.first(where: { $0.id == planId }) else { return }
        plan.packingList[item] = !(plan.packingList[item] ?? false)
        try await update(plan)
    }

    public func addPackingItem(planId: String, item: String) async throws {
        guard var plan = plans.first(where: { $0.id == planId }) else { return }
        plan.packingList[item] = false
        try await update(plan)
    }

    public func removePackingItem(planId: String, item: String) async throws {
        guard var plan = plans.first(where: { $0.id == planId }) else { return }
        plan.packingList.removeValue(forKey: item)
        try await update(plan)
    }

    public func toggleDocument(planId: String, document: String) async throws {
        guard var plan = plans.first(where: { $0.id == planId }) else { return }
        plan.documents[document] = !(plan.documents[document] ?? false)
        try await update(plan)
    }

    public func updateNotes(planId: String, notes: String) async throws {
        guard var plan = plans.first(where: { $0.id == planId }) else { return }
        plan.notes = notes
        try await update(plan)
    }

    /// Seeds default packing/documents checklists once (no-op when packing
    /// already exists), matching the Dart behavior.
    public func initPackingAndDocs(planId: String) async throws {
        guard var plan = plans.first(where: { $0.id == planId }),
              plan.packingList.isEmpty
        else { return }
        plan.packingList = TravelPlan.defaultPacking(for: plan.type)
        plan.documents = TravelPlan.defaultDocuments
        try await update(plan)
    }

    // MARK: - Visited & wishlist

    public func addVisited(_ country: VisitedCountry) async throws {
        guard !visited.contains(where: { $0.name == country.name }) else { return }
        try await database.writer.write { db in try country.insert(db) }
        visited.append(country)
        engram?.note(
            agentId: SphereType.travel.rawValue,
            content: "Visited \(country.name)" + (country.year.map { " (\($0))" } ?? ""),
            tags: ["log", "travel", "visited"]
        )
    }

    public func removeVisited(name: String) async throws {
        _ = try await database.writer.write { db in try VisitedCountry.deleteOne(db, key: name) }
        visited.removeAll { $0.name == name }
    }

    public func addWishlist(_ destination: WishlistDestination) async throws {
        try await database.writer.write { db in try destination.insert(db) }
        wishlist.append(destination)
    }

    public func removeWishlist(id: String) async throws {
        _ = try await database.writer.write { db in try WishlistDestination.deleteOne(db, key: id) }
        wishlist.removeAll { $0.id == id }
    }

    // MARK: - Agent tools

    /// NEW relative to the Dart version (which had no travel tools): a write
    /// tool for dream-list additions — the Travel agent's most natural action
    /// when recommending destinations — and a silent summary lookup.
    public nonisolated var tools: [SphereTool] {
        [
            SphereTool(
                definition: LLMTool(
                    name: "add_wishlist_destination",
                    description: "Add a destination to the user's travel dream list. Use when "
                        + "the user says they want to visit a place someday.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "destination": ["type": "string", "minLength": 1],
                            "country": ["type": "string"],
                            "flag": ["type": "string", "description": "Flag emoji, e.g. 🇯🇵"],
                            "note": ["type": "string"],
                        ],
                        "required": ["destination"],
                    ]
                ),
                spheres: [.travel],
                confirmation: { input in
                    "Added to dream list: \(input["destination"]?.stringValue ?? "")"
                },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let destination = input["destination"]?.stringValue, !destination.isEmpty else {
                        throw AgentToolInputError("destination is required")
                    }
                    let wish = WishlistDestination(
                        id: WishlistDestination.newID(),
                        destination: destination,
                        country: input["country"]?.stringValue ?? "",
                        flag: input["flag"]?.stringValue ?? "🌍",
                        note: input["note"]?.stringValue ?? ""
                    )
                    try await self.addWishlist(wish)
                    return JSONValue.object(["ok": true, "id": .string(wish.id)]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "get_travel_summary",
                    description: "Look up the user's travel state: next booked trip with "
                        + "countdown, upcoming plans, countries visited, and the dream list. "
                        + "Use before discussing trips or recommendations.",
                    inputSchema: ["type": "object", "properties": [:], "required": []]
                ),
                spheres: [.travel],
                silent: true,
                handler: { [weak self] _ in
                    guard let self else { throw CancellationError() }
                    return await self.travelSummaryJSON()
                }
            ),
        ]
    }

    private func travelSummaryJSON() -> String {
        var summary: [String: JSONValue] = [
            "trips": .array(plans.map { plan in
                var fields: [String: JSONValue] = [
                    "destination": .string(plan.destination),
                    "type": .string(plan.type.rawValue),
                    "status": .string(plan.status.rawValue),
                ]
                if let days = plan.daysUntil() {
                    fields["daysUntil"] = .number(Double(days))
                }
                return .object(fields)
            }),
            "visitedCountries": .array(visited.map { .string($0.name) }),
            "dreamList": .array(wishlist.map { wish in
                .object([
                    "destination": .string(wish.destination),
                    "country": .string(wish.country),
                ])
            }),
        ]
        if let next = nextTrip(), let days = next.daysUntil() {
            summary["nextTrip"] = .object([
                "destination": .string(next.destination),
                "daysUntil": .number(Double(days)),
            ])
        }
        return JSONValue.object(summary).encodedString()
    }
}

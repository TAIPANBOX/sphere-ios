import Foundation
import GRDB
import Observation

/// Home sphere store: household tasks, plant watering, and the shopping
/// list. Follows the golden-template shape (docs/HANDOFF.md).
@MainActor
@Observable
public final class HomeSphereStore {
    public private(set) var tasks: [HomeTask] = []
    public private(set) var plants: [Plant] = []
    public private(set) var shopping: [ShoppingItem] = []

    private let database: AppDatabase
    private let engram: EngramStore?

    public init(database: AppDatabase, engram: EngramStore? = nil) {
        self.database = database
        self.engram = engram
    }

    public func load() async throws {
        let (tasks, plants, shopping) = try await database.writer.read { db in
            (
                try HomeTask.fetchAll(db),
                try Plant.fetchAll(db),
                try ShoppingItem.fetchAll(db)
            )
        }
        self.tasks = tasks
        self.plants = plants
        self.shopping = shopping
    }

    // MARK: - Tasks

    public func add(_ task: HomeTask) async throws {
        try await database.writer.write { db in try task.insert(db) }
        tasks.append(task)
        engram?.note(
            agentId: SphereType.home.rawValue,
            content: "New home task: \(task.title) (\(task.category.rawValue))",
            tags: ["log", "home", "task"]
        )
    }

    public func toggle(id: String) async throws {
        guard var task = tasks.first(where: { $0.id == id }) else { return }
        task.status = task.status == .done ? .todo : .done
        try await database.writer.write { [task] db in try task.save(db) }
        tasks = tasks.map { $0.id == id ? task : $0 }
    }

    public func remove(id: String) async throws {
        _ = try await database.writer.write { db in try HomeTask.deleteOne(db, key: id) }
        tasks.removeAll { $0.id == id }
    }

    public var openTasks: [HomeTask] {
        tasks.filter { $0.status == .todo }
    }

    /// Open tasks whose due day is before today (feeds Today's Focus).
    public func overdueTasks(asOf now: Date = Date()) -> [HomeTask] {
        let today = Calendar.current.startOfDay(for: now)
        return tasks.filter { task in
            guard task.status == .todo, let dueDate = task.dueDate else { return false }
            return Calendar.current.startOfDay(for: dueDate) < today
        }
    }

    /// Open tasks scheduled exactly today (feeds Today's Focus).
    public func tasksDueToday(asOf now: Date = Date()) -> [HomeTask] {
        tasks.filter { task in
            guard task.status == .todo, let dueDate = task.dueDate else { return false }
            return Calendar.current.isDate(dueDate, inSameDayAs: now)
        }
    }

    // MARK: - Plants

    public func addPlant(_ plant: Plant) async throws {
        try await database.writer.write { db in try plant.insert(db) }
        plants.append(plant)
    }

    public func removePlant(id: String) async throws {
        _ = try await database.writer.write { db in try Plant.deleteOne(db, key: id) }
        plants.removeAll { $0.id == id }
    }

    public func water(id: String, on date: Date = Date()) async throws {
        guard let plant = plants.first(where: { $0.id == id }) else { return }
        let watered = plant.watered(on: date)
        try await database.writer.write { db in try watered.save(db) }
        plants = plants.map { $0.id == id ? watered : $0 }
    }

    public func needsWateringCount(asOf now: Date = Date()) -> Int {
        plants.count { $0.needsWatering(asOf: now) }
    }

    // MARK: - Shopping

    public func addShoppingItem(_ item: ShoppingItem) async throws {
        try await database.writer.write { db in try item.insert(db) }
        shopping.append(item)
    }

    public func toggleShoppingItem(id: String) async throws {
        guard var item = shopping.first(where: { $0.id == id }) else { return }
        item.checked.toggle()
        try await database.writer.write { [item] db in try item.save(db) }
        shopping = shopping.map { $0.id == id ? item : $0 }
    }

    public func removeShoppingItem(id: String) async throws {
        _ = try await database.writer.write { db in try ShoppingItem.deleteOne(db, key: id) }
        shopping.removeAll { $0.id == id }
    }

    public func clearChecked() async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM shopping_items WHERE checked = 1")
        }
        shopping.removeAll(where: \.checked)
    }

    public var uncheckedCount: Int {
        shopping.count { !$0.checked }
    }

    // MARK: - Agent tools

    /// NEW relative to the Dart version (which had no home tools), following
    /// the wave-2 write + silent-lookup convention.
    public nonisolated var tools: [SphereTool] {
        [
            SphereTool(
                definition: LLMTool(
                    name: "add_home_task",
                    description: "Create a household task (cleaning, repair, garden, bills…). "
                        + "Use when the user mentions something to do around the house.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string", "minLength": 1],
                            "category": [
                                "type": "string",
                                "enum": [
                                    "cleaning", "repair", "organization", "garden",
                                    "shopping", "bills", "other",
                                ],
                            ],
                            "dueDate": [
                                "type": "string",
                                "description": "Optional ISO-8601 date (YYYY-MM-DD)",
                            ],
                        ],
                        "required": ["title"],
                    ]
                ),
                spheres: [.home],
                confirmation: { input in
                    "Added home task: \(input["title"]?.stringValue ?? "")"
                },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let title = input["title"]?.stringValue, !title.isEmpty else {
                        throw AgentToolInputError("title is required")
                    }
                    let task = HomeTask(
                        id: HomeTask.newID(),
                        title: title,
                        category: input["category"]?.stringValue
                            .flatMap(HomeCategory.init(rawValue:)) ?? .other,
                        dueDate: input["dueDate"]?.stringValue.flatMap(CareerStore.parseDueDate),
                        createdAt: Date()
                    )
                    try await self.add(task)
                    return JSONValue.object(["ok": true, "id": .string(task.id)]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "add_shopping_item",
                    description: "Add an item to the user's shopping list. Use when they "
                        + "mention needing to buy something.",
                    inputSchema: [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string", "minLength": 1],
                            "category": ["type": "string", "description": "e.g. Groceries"],
                        ],
                        "required": ["name"],
                    ]
                ),
                spheres: [.home],
                confirmation: { input in
                    "Added to shopping list: \(input["name"]?.stringValue ?? "")"
                },
                handler: { [weak self] input in
                    guard let self else { throw CancellationError() }
                    guard let name = input["name"]?.stringValue, !name.isEmpty else {
                        throw AgentToolInputError("name is required")
                    }
                    let item = ShoppingItem(
                        id: ShoppingItem.newID(),
                        name: name,
                        category: input["category"]?.stringValue ?? "General"
                    )
                    try await self.addShoppingItem(item)
                    return JSONValue.object(["ok": true, "id": .string(item.id)]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(
                    name: "get_home_summary",
                    description: "Look up the household state: open tasks (with overdue "
                        + "flags), plants that need watering, and the shopping list.",
                    inputSchema: ["type": "object", "properties": [:], "required": []]
                ),
                spheres: [.home],
                silent: true,
                handler: { [weak self] _ in
                    guard let self else { throw CancellationError() }
                    return await self.homeSummaryJSON()
                }
            ),
        ]
    }

    private func homeSummaryJSON() -> String {
        let overdueIds = Set(overdueTasks().map(\.id))
        return JSONValue.object([
            "openTasks": .array(openTasks.map { task in
                var fields: [String: JSONValue] = [
                    "title": .string(task.title),
                    "category": .string(task.category.rawValue),
                    "overdue": .bool(overdueIds.contains(task.id)),
                ]
                if let dueDate = task.dueDate {
                    fields["due"] = .string(DayKey.make(dueDate))
                }
                return .object(fields)
            }),
            "plantsNeedingWater": .array(
                plants.filter { $0.needsWatering() }.map { .string($0.name) }
            ),
            "shoppingList": .array(
                shopping.filter { !$0.checked }.map { .string($0.name) }
            ),
        ]).encodedString()
    }
}

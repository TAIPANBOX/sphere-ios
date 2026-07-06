import SwiftUI
import SphereCore

public struct HomeSphereScreen: View {
    private let store: HomeSphereStore
    @State private var showingAddTask = false
    @State private var showingAddPlant = false
    @State private var newShoppingItem = ""

    private let accent = SphereTheme.accent(for: .home)

    public init(store: HomeSphereStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.tasks.isEmpty && store.plants.isEmpty && store.shopping.isEmpty {
                    EmptyStateCard(
                        emoji: "🏠",
                        accent: accent,
                        title: uiString("Start your Home sphere"),
                        message: uiString("Add a household task, a plant to keep alive, or the next thing you need to buy."),
                        buttonLabel: uiString("Add your first task")
                    ) {
                        showingAddTask = true
                    }
                }
                if !store.warrantyExpiringSoon().isEmpty {
                    warrantyCard
                }
                tasksSection
                plantsSection
                shoppingSection
                moreSection
            }
            .padding()
        }
        .navigationTitle(Text(ui: "Home sphere"))
        .toolbar {
            Menu {
                Button { showingAddTask = true } label: { Text(ui: "Add Task") }
                Button { showingAddPlant = true } label: { Text(ui: "Add Plant") }
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddTask) {
            AddHomeTaskSheet { task in
                Task { try? await store.add(task) }
            }
        }
        .sheet(isPresented: $showingAddPlant) {
            AddPlantSheet { plant in
                Task { try? await store.addPlant(plant) }
            }
        }
        .task {
            try? await store.load()
        }
    }

    // MARK: - Warranty radar (gem)

    private var warrantyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { Text(ui: "Warranties ending soon") } icon: { Image(systemName: "shield.lefthalf.filled") }
                .font(.headline).foregroundStyle(.orange)
            ForEach(store.warrantyExpiringSoon()) { appliance in
                HStack {
                    Text(appliance.name).font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(appliance.warrantyDaysLeft() ?? 0)d left")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    // MARK: - More (appliances, utilities, renovation, inventory)

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui: "More").font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                MoreLink(uiString("Appliances"), systemImage: "washer.fill",
                         count: store.appliances.isEmpty ? nil : store.appliances.count) { appliancesList }
                Divider().padding(.leading, 38)
                MoreLink(uiString("Utilities"), systemImage: "bolt.fill",
                         count: store.utilityReadings.isEmpty ? nil : store.utilityReadings.count) { utilitiesList }
                Divider().padding(.leading, 38)
                MoreLink(uiString("Renovation"), systemImage: "hammer.fill",
                         count: store.renovations.isEmpty ? nil : store.renovations.count) { renovationList }
                Divider().padding(.leading, 38)
                MoreLink(uiString("Inventory"), systemImage: "shippingbox.fill",
                         count: store.inventory.isEmpty ? nil : store.inventory.count) { inventoryList }
            }
            .sphereCard()
        }
    }

    private var appliancesList: some View {
        CRUDListScreen(
            title: uiString("Appliances"),
            items: store.appliances,
            emptyTitle: uiString("No appliances tracked"),
            emptySystemImage: "washer",
            addSheet: { AddApplianceSheet { a in Task { try? await store.addAppliance(a) } } },
            row: { appliance in
                VStack(alignment: .leading, spacing: 2) {
                    Text(appliance.name).font(.body.weight(.medium))
                    if let days = appliance.warrantyDaysLeft() {
                        Text(days >= 0 ? uiString("Warranty: \(days)d left") : uiString("Warranty expired"))
                            .font(.caption)
                            .foregroundStyle(days >= 0 ? Color.secondary : Color.red)
                    } else if !appliance.brand.isEmpty {
                        Text(appliance.brand).font(.caption).foregroundStyle(.secondary)
                    }
                }
            },
            onDelete: { a in Task { try? await store.removeAppliance(id: a.id) } },
            onRestore: { a in Task { try? await store.addAppliance(a) } }
        )
    }

    private var utilitiesList: some View {
        CRUDListScreen(
            title: uiString("Utilities"),
            items: store.utilityReadings,
            emptyTitle: uiString("No readings yet"),
            emptySystemImage: "bolt",
            addSheet: { AddUtilitySheet { r in Task { try? await store.addUtilityReading(r) } } },
            row: { reading in
                HStack(spacing: 10) {
                    Text(reading.kind.emoji)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(reading.kind.rawValue.capitalized) · \(Int(reading.value))")
                            .font(.body.weight(.medium))
                        Text(reading.date, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if reading.cost > 0 {
                        Text(String(format: "%.0f", reading.cost)).font(.subheadline.weight(.semibold))
                    }
                }
            },
            onDelete: { r in Task { try? await store.removeUtilityReading(id: r.id) } },
            onRestore: { r in Task { try? await store.addUtilityReading(r) } }
        )
    }

    private var renovationList: some View {
        CRUDListScreen(
            title: uiString("Renovation"),
            items: store.renovations,
            emptyTitle: uiString("No projects"),
            emptySystemImage: "hammer",
            addSheet: { AddRenovationSheet { p in Task { try? await store.addRenovation(p) } } },
            row: { project in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(project.name).font(.body.weight(.medium))
                        Spacer()
                        Text(project.status.label).font(.caption).foregroundStyle(.secondary)
                    }
                    if project.budget > 0 {
                        ProgressView(value: min(project.spent / project.budget, 1)).tint(accent)
                        Text("\(Int(project.spent)) / \(Int(project.budget))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            },
            onDelete: { p in Task { try? await store.removeRenovation(id: p.id) } },
            onRestore: { p in Task { try? await store.addRenovation(p) } }
        )
    }

    private var inventoryList: some View {
        CRUDListScreen(
            title: uiString("Inventory"),
            items: store.inventory,
            emptyTitle: uiString("Nothing catalogued"),
            emptySystemImage: "shippingbox",
            addSheet: { AddInventorySheet { i in Task { try? await store.addInventoryItem(i) } } },
            row: { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.quantity > 1 ? "\(item.name) ×\(item.quantity)" : item.name)
                            .font(.body.weight(.medium))
                        if item.isLentOut {
                            Text("Lent to \(item.lentTo)").font(.caption).foregroundStyle(.orange)
                        } else if !item.location.isEmpty {
                            Text(item.location).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            },
            onDelete: { i in Task { try? await store.removeInventoryItem(id: i.id) } },
            onRestore: { i in Task { try? await store.addInventoryItem(i) } }
        )
    }

    // MARK: - Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ui: "Household Tasks").font(.title3.weight(.semibold))
                Spacer()
                if !store.overdueTasks().isEmpty {
                    Text("\(store.overdueTasks().count) overdue")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
            if store.openTasks.isEmpty {
                Text(ui: "Nothing to do around the house 🎉")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(store.openTasks) { task in
                HStack(spacing: 12) {
                    Button {
                        Task { try? await store.toggle(id: task.id) }
                    } label: {
                        Image(systemName: "circle").font(.title3).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Text(task.category.emoji)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title).font(.body.weight(.medium))
                        HStack(spacing: 6) {
                            Text(task.category.label)
                            if let dueDate = task.dueDate {
                                Text("· due \(dueDate, style: .date)")
                            }
                            if task.isRecurring {
                                Text("· ↻")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(
                            store.overdueTasks().contains { $0.id == task.id }
                                ? Color.red : Color.secondary
                        )
                    }
                    Spacer()
                    Menu {
                        Button(role: .destructive) {
                            Task { try? await store.remove(id: task.id) }
                        } label: {
                            Text(ui: "Delete")
                        }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(.secondary)
                    }
                }
                .sphereCard()
            }
        }
    }

    // MARK: - Plants

    private var plantsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ui: "Plants").font(.title3.weight(.semibold))
                Spacer()
                if store.needsWateringCount() > 0 {
                    Text("💧 \(store.needsWateringCount()) thirsty")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
            ForEach(store.plants) { plant in
                HStack(spacing: 12) {
                    Text(plant.emoji).font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plant.name).font(.body.weight(.medium))
                        Text(
                            plant.needsWatering()
                                ? uiString("Needs watering")
                                : uiString("Water in \(plant.daysUntilWatering()) d")
                        )
                        .font(.caption)
                        .foregroundStyle(plant.needsWatering() ? Color.blue : Color.secondary)
                    }
                    Spacer()
                    Button {
                        Task { try? await store.water(id: plant.id) }
                    } label: {
                        Image(systemName: "drop.fill")
                            .foregroundStyle(plant.needsWatering() ? .blue : .secondary)
                    }
                    .buttonStyle(.bordered)
                }
                .sphereCard()
            }
        }
    }

    // MARK: - Shopping

    private var shoppingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ui: "Shopping List").font(.title3.weight(.semibold))
                Spacer()
                if store.shopping.contains(where: \.checked) {
                    Button {
                        Task { try? await store.clearChecked() }
                    } label: {
                        Text(ui: "Clear done")
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            HStack {
                TextField(text: $newShoppingItem) { Text(ui: "Add item…") }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addShoppingItem)
                Button(action: addShoppingItem) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .disabled(newShoppingItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(store.shopping) { item in
                HStack(spacing: 12) {
                    Button {
                        Task { try? await store.toggleShoppingItem(id: item.id) }
                    } label: {
                        Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.checked ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    Text(item.name).strikethrough(item.checked)
                    Spacer()
                    Text(item.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .sphereCard()
            }
        }
    }

    private func addShoppingItem() {
        let name = newShoppingItem.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newShoppingItem = ""
        Task {
            try? await store.addShoppingItem(ShoppingItem(id: ShoppingItem.newID(), name: name))
        }
    }
}

struct AddHomeTaskSheet: View {
    let onAdd: (HomeTask) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var category = HomeCategory.cleaning
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var isRecurring = false
    @State private var recurrenceDays = 7

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $title) { Text(ui: "Task") }
                Picker(selection: $category) {
                    ForEach(HomeCategory.allCases, id: \.self) { category in
                        Text("\(category.emoji) \(category.label)").tag(category)
                    }
                } label: { Text(ui: "Category") }
                Toggle(isOn: $hasDueDate) { Text(ui: "Due date") }
                if hasDueDate {
                    DatePicker(selection: $dueDate, displayedComponents: .date) { Text(ui: "Due") }
                }
                Toggle(isOn: $isRecurring) { Text(ui: "Recurring") }
                if isRecurring {
                    Stepper(value: $recurrenceDays, in: 1...90) { Text(ui: "Every \(recurrenceDays) days") }
                }
            }
            .navigationTitle(Text(ui: "New Home Task"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(HomeTask(
                            id: HomeTask.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            category: category,
                            dueDate: hasDueDate ? dueDate : nil,
                            isRecurring: isRecurring,
                            recurrenceDays: isRecurring ? recurrenceDays : 0,
                            createdAt: Date()
                        ))
                        dismiss()
                    } label: {
                        Text(ui: "Add")
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddPlantSheet: View {
    let onAdd: (Plant) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🌿"
    @State private var intervalDays = 3

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $name) { Text(ui: "Plant name") }
                TextField(text: $emoji) { Text(ui: "Emoji") }
                Stepper(value: $intervalDays, in: 1...30) { Text(ui: "Water every \(intervalDays) d") }
            }
            .navigationTitle(Text(ui: "New Plant"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(Plant(
                            id: Plant.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            emoji: emoji.isEmpty ? "🌿" : emoji,
                            intervalDays: intervalDays
                        ))
                        dismiss()
                    } label: {
                        Text(ui: "Add")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddApplianceSheet: View {
    let onAdd: (Appliance) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brand = ""
    @State private var hasWarranty = false
    @State private var warrantyUntil = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $name) { Text(ui: "Name (e.g. Washing machine)") }
                TextField(text: $brand) { Text(ui: "Brand") }
                Toggle(isOn: $hasWarranty) { Text(ui: "Has warranty") }
                if hasWarranty {
                    DatePicker(selection: $warrantyUntil, displayedComponents: .date) { Text(ui: "Warranty until") }
                }
            }
            .navigationTitle(Text(ui: "Add Appliance"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Text(ui: "Cancel") } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(Appliance(
                            id: Appliance.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            brand: brand.trimmingCharacters(in: .whitespaces),
                            warrantyUntil: hasWarranty ? warrantyUntil : nil
                        ))
                        dismiss()
                    } label: {
                        Text(ui: "Add")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddUtilitySheet: View {
    let onAdd: (UtilityReading) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind = UtilityKind.electricity
    @State private var valueText = ""
    @State private var costText = ""

    private var value: Double? { Double(valueText.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            Form {
                Picker(selection: $kind) {
                    ForEach(UtilityKind.allCases, id: \.self) { k in
                        Text("\(k.emoji) \(k.rawValue.capitalized)").tag(k)
                    }
                } label: { Text(ui: "Utility") }
                TextField(text: $valueText) { Text(ui: "Meter reading") }
                TextField(text: $costText) { Text(ui: "Cost (optional)") }
            }
            .navigationTitle(Text(ui: "Add Reading"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Text(ui: "Cancel") } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(UtilityReading(
                            id: UtilityReading.newID(),
                            kind: kind,
                            value: value ?? 0,
                            cost: Double(costText.replacingOccurrences(of: ",", with: ".")) ?? 0,
                            date: Date()
                        ))
                        dismiss()
                    } label: {
                        Text(ui: "Add")
                    }
                    .disabled(value == nil)
                }
            }
        }
    }
}

struct AddRenovationSheet: View {
    let onAdd: (RenovationProject) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var status = RenovationStatus.planning
    @State private var budgetText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $name) { Text(ui: "Project (e.g. Kitchen remodel)") }
                Picker(selection: $status) {
                    ForEach(RenovationStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                } label: { Text(ui: "Status") }
                TextField(text: $budgetText) { Text(ui: "Budget (optional)") }
            }
            .navigationTitle(Text(ui: "Add Project"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Text(ui: "Cancel") } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(RenovationProject(
                            id: RenovationProject.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            status: status,
                            budget: Double(budgetText.replacingOccurrences(of: ",", with: ".")) ?? 0
                        ))
                        dismiss()
                    } label: {
                        Text(ui: "Add")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddInventorySheet: View {
    let onAdd: (InventoryItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var quantity = 1
    @State private var location = ""
    @State private var lentTo = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $name) { Text(ui: "Item") }
                Stepper(value: $quantity, in: 1...999) { Text(ui: "Quantity: \(quantity)") }
                TextField(text: $location) { Text(ui: "Location (e.g. Garage)") }
                TextField(text: $lentTo) { Text(ui: "Lent to (if anyone)") }
            }
            .navigationTitle(Text(ui: "Add Item"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Text(ui: "Cancel") } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(InventoryItem(
                            id: InventoryItem.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            quantity: quantity,
                            location: location.trimmingCharacters(in: .whitespaces),
                            lentTo: lentTo.trimmingCharacters(in: .whitespaces)
                        ))
                        dismiss()
                    } label: {
                        Text(ui: "Add")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

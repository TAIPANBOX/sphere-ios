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
                tasksSection
                plantsSection
                shoppingSection
            }
            .padding()
        }
        .navigationTitle("Home")
        .toolbar {
            Menu {
                Button("Add Task") { showingAddTask = true }
                Button("Add Plant") { showingAddPlant = true }
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

    // MARK: - Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Household Tasks").font(.title3.weight(.semibold))
                Spacer()
                if !store.overdueTasks().isEmpty {
                    Text("\(store.overdueTasks().count) overdue")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
            if store.openTasks.isEmpty {
                Text("Nothing to do around the house 🎉")
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
                        Button("Delete", role: .destructive) {
                            Task { try? await store.remove(id: task.id) }
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
                Text("Plants").font(.title3.weight(.semibold))
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
                                ? "Needs watering"
                                : "Water in \(plant.daysUntilWatering()) d"
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
                Text("Shopping List").font(.title3.weight(.semibold))
                Spacer()
                if store.shopping.contains(where: \.checked) {
                    Button("Clear done") {
                        Task { try? await store.clearChecked() }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            HStack {
                TextField("Add item…", text: $newShoppingItem)
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

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task", text: $title)
                Picker("Category", selection: $category) {
                    ForEach(HomeCategory.allCases, id: \.self) { category in
                        Text("\(category.emoji) \(category.label)").tag(category)
                    }
                }
                Toggle("Due date", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                }
                Toggle("Recurring", isOn: $isRecurring)
            }
            .navigationTitle("New Home Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(HomeTask(
                            id: HomeTask.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            category: category,
                            dueDate: hasDueDate ? dueDate : nil,
                            isRecurring: isRecurring,
                            createdAt: Date()
                        ))
                        dismiss()
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
                TextField("Plant name", text: $name)
                TextField("Emoji", text: $emoji)
                Stepper("Water every \(intervalDays) d", value: $intervalDays, in: 1...30)
            }
            .navigationTitle("New Plant")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(Plant(
                            id: Plant.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            emoji: emoji.isEmpty ? "🌿" : emoji,
                            intervalDays: intervalDays
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

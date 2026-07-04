import SwiftUI
import SphereCore

public struct CareerScreen: View {
    private let store: CareerStore
    @State private var showingAddTask = false
    @State private var showingAddInterview = false
    @State private var showingAddAchievement = false
    @State private var showingAddContact = false

    private let accent = SphereTheme.accent(for: .career)

    public init(store: CareerStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statsCard
                tasksSection
                projectsSection
                interviewsSection
                achievementsSection
                networkSection
            }
            .padding()
        }
        .navigationTitle("Career")
        .toolbar {
            Menu {
                Button("Add Task") { showingAddTask = true }
                Button("Add Interview") { showingAddInterview = true }
                Button("Add Achievement") { showingAddAchievement = true }
                Button("Add Contact") { showingAddContact = true }
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddTask) {
            AddCareerTaskSheet { task in
                Task { try? await store.add(task) }
            }
        }
        .sheet(isPresented: $showingAddInterview) {
            AddInterviewSheet { interview in
                Task { try? await store.addInterview(interview) }
            }
        }
        .sheet(isPresented: $showingAddAchievement) {
            AddAchievementSheet { achievement in
                Task { try? await store.addAchievement(achievement) }
            }
        }
        .sheet(isPresented: $showingAddContact) {
            AddNetworkContactSheet { contact in
                Task { try? await store.addNetworkContact(contact) }
            }
        }
        .task {
            try? await store.load()
        }
    }

    // MARK: - Stats

    private var statsCard: some View {
        HStack(spacing: 0) {
            statColumn("Open", value: store.openTasks.count, tint: accent)
            Divider().frame(height: 40)
            statColumn("Done", value: store.doneCount, tint: .green)
            Divider().frame(height: 40)
            statColumn("Overdue", value: store.overdueCount(), tint: .red)
        }
        .sphereCard()
    }

    private func statColumn(_ title: String, value: Int, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.title3.weight(.bold)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tasks").font(.title3.weight(.semibold))
            if store.openTasks.isEmpty {
                Text("All clear — add a task or tell your agent.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(store.openTasks) { task in
                HStack(spacing: 12) {
                    Button {
                        Task { try? await store.toggleStatus(id: task.id) }
                    } label: {
                        Image(systemName: "circle").font(.title3).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title).font(.body.weight(.medium))
                        HStack(spacing: 6) {
                            Text(task.priority.emoji + " " + task.priority.label)
                            if !task.project.isEmpty {
                                Text("· \(task.project)")
                            }
                            if let dueDate = task.dueDate {
                                Text("· due \(dueDate, style: .date)")
                                    .foregroundStyle(task.isOverdue() ? .red : .secondary)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    // MARK: - Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Projects").font(.title3.weight(.semibold))
            if store.activeProjects.isEmpty {
                Text("No active projects.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(store.activeProjects) { project in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(project.status.emoji) \(project.name)")
                            .font(.body.weight(.medium))
                        Spacer()
                        if let days = project.daysRemaining() {
                            Text(days >= 0 ? "\(days) d left" : "\(-days) d over")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(days >= 0 ? Color.secondary : Color.red)
                        }
                    }
                    if !project.role.isEmpty {
                        Text(project.role).font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(project.progressPercent), total: 100)
                        .tint(accent)
                    Text("\(project.progressPercent)%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                }
                .sphereCard()
            }
        }
    }

    // MARK: - Interviews

    private var interviewsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Interviews").font(.title3.weight(.semibold))
            if store.interviews.isEmpty {
                Text("No applications tracked.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(store.interviews) { interview in
                HStack(spacing: 12) {
                    Text(interview.status.emoji)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(interview.company).font(.body.weight(.medium))
                        Text(interview.position).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(InterviewStatus.allCases, id: \.self) { status in
                            Button("\(status.emoji) \(status.label)") {
                                Task { try? await store.setInterviewStatus(id: interview.id, status: status) }
                            }
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            Task { try? await store.removeInterview(id: interview.id) }
                        }
                    } label: {
                        Text(interview.status.label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(badgeColor(interview.status).opacity(0.15), in: Capsule())
                            .foregroundStyle(badgeColor(interview.status))
                    }
                }
                .sphereCard()
            }
        }
    }

    private func badgeColor(_ status: InterviewStatus) -> Color {
        if status.isPositive { return .green }
        if status.isNegative { return .red }
        return accent
    }

    // MARK: - Achievements

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Achievements").font(.title3.weight(.semibold))
            if store.achievements.isEmpty {
                Text("Log a win worth remembering.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(store.achievements) { achievement in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("🏆 \(achievement.title)").font(.body.weight(.medium))
                        Spacer()
                        Text(achievement.date, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !achievement.impact.isEmpty {
                        Text(achievement.impact).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .sphereCard()
                .swipeActions {
                    Button(role: .destructive) {
                        Task { try? await store.removeAchievement(id: achievement.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Network

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Network").font(.title3.weight(.semibold))
                Spacer()
                if !store.staleContacts().isEmpty {
                    Text("\(store.staleContacts().count) to reconnect")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            ForEach(store.network) { contact in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name).font(.body.weight(.medium))
                        Text([contact.role, contact.company]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    let stale = contact.daysSinceContact() >= 60
                    Button {
                        Task { try? await store.markNetworkContacted(id: contact.id) }
                    } label: {
                        Text(contact.lastContact == nil ? "Reach out" : "\(contact.daysSinceContact())d")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(stale ? Color.orange : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .sphereCard()
                .swipeActions {
                    Button(role: .destructive) {
                        Task { try? await store.removeNetworkContact(id: contact.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }
}

struct AddCareerTaskSheet: View {
    let onAdd: (CareerTask) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var project = ""
    @State private var priority = TaskPriority.medium
    @State private var hasDueDate = false
    @State private var dueDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task title", text: $title)
                TextField("Project (optional)", text: $project)
                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Text("\(priority.emoji) \(priority.label)").tag(priority)
                    }
                }
                Toggle("Due date", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                }
            }
            .navigationTitle("New Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(CareerTask(
                            id: CareerTask.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            project: project.trimmingCharacters(in: .whitespaces),
                            priority: priority,
                            dueDate: hasDueDate ? dueDate : nil,
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

struct AddAchievementSheet: View {
    let onAdd: (Achievement) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var impact = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Achievement", text: $title)
                TextField("Impact (optional)", text: $impact)
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("Log Achievement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(Achievement(
                            id: Achievement.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            date: date,
                            impact: impact.trimmingCharacters(in: .whitespaces)
                        ))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddNetworkContactSheet: View {
    let onAdd: (NetworkContact) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role = ""
    @State private var company = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Role", text: $role)
                TextField("Company", text: $company)
                TextField("Note", text: $note)
            }
            .navigationTitle("Add Contact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(NetworkContact(
                            id: NetworkContact.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            role: role.trimmingCharacters(in: .whitespaces),
                            company: company.trimmingCharacters(in: .whitespaces),
                            note: note.trimmingCharacters(in: .whitespaces)
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddInterviewSheet: View {
    let onAdd: (Interview) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var company = ""
    @State private var position = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Company", text: $company)
                TextField("Position", text: $position)
            }
            .navigationTitle("New Application")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(Interview(
                            id: Interview.newID(),
                            company: company.trimmingCharacters(in: .whitespaces),
                            position: position.trimmingCharacters(in: .whitespaces),
                            appliedDate: Date()
                        ))
                        dismiss()
                    }
                    .disabled(company.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

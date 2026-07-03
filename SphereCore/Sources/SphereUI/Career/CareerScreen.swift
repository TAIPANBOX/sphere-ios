import SwiftUI
import SphereCore

public struct CareerScreen: View {
    private let store: CareerStore
    @State private var showingAddTask = false
    @State private var showingAddInterview = false

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
            }
            .padding()
        }
        .navigationTitle("Career")
        .toolbar {
            Menu {
                Button("Add Task") { showingAddTask = true }
                Button("Add Interview") { showingAddInterview = true }
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

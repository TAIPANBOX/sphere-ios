import SwiftUI
import SphereCore

public struct CareerScreen: View {
    private let store: CareerStore
    private let agent: AgentService?
    private let onConfigureProvider: (() -> Void)?
    @State private var showingAddTask = false
    @State private var showingAddInterview = false
    @State private var showingAddAchievement = false
    @State private var showingAddContact = false

    private let accent = SphereTheme.accent(for: .career)

    public init(
        store: CareerStore,
        agent: AgentService? = nil,
        onConfigureProvider: (() -> Void)? = nil
    ) {
        self.store = store
        self.agent = agent
        self.onConfigureProvider = onConfigureProvider
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.tasks.isEmpty && store.network.isEmpty {
                    EmptyStateCard(
                        emoji: "💼",
                        accent: accent,
                        title: uiString("Start your Career sphere"),
                        message: uiString("Add a task you're on the hook for, or someone in your network worth staying close to."),
                        buttonLabel: uiString("Add your first task")
                    ) {
                        showingAddTask = true
                    }
                }
                statsCard
                tasksSection
                projectsSection
                interviewsSection
                achievementsSection
                networkSection
                moreSection
            }
            .padding()
        }
        .navigationTitle(Text(ui: "Career"))
        .toolbar {
            Menu {
                Button { showingAddTask = true } label: { Text(ui: "Add Task") }
                Button { showingAddInterview = true } label: { Text(ui: "Add Interview") }
                Button { showingAddAchievement = true } label: { Text(ui: "Add Achievement") }
                Button { showingAddContact = true } label: { Text(ui: "Add Contact") }
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

    // MARK: - More (skills, salary, goals, 1:1s, brag doc)

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui: "More").font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                MoreLink(uiString("Skills"), systemImage: "star.fill",
                         count: store.careerSkills.isEmpty ? nil : store.careerSkills.count) { skillsList }
                Divider().padding(.leading, 38)
                MoreLink(uiString("Salary history"), systemImage: "banknote.fill",
                         count: store.salaryHistory.isEmpty ? nil : store.salaryHistory.count) { salaryList }
                Divider().padding(.leading, 38)
                MoreLink(uiString("Career goals"), systemImage: "target",
                         count: store.careerGoals.isEmpty ? nil : store.careerGoals.count) { goalsList }
                Divider().padding(.leading, 38)
                MoreLink(uiString("1:1 notes"), systemImage: "person.2.fill",
                         count: store.oneOnOnes.isEmpty ? nil : store.oneOnOnes.count) { oneOnOnesList }
                Divider().padding(.leading, 38)
                MoreLink(uiString("Brag document"), systemImage: "doc.text.fill") { bragDocumentView }
                if agent != nil {
                    Divider().padding(.leading, 38)
                    MoreLink(uiString("Interview prep"), systemImage: "person.crop.rectangle.badge.plus") {
                        InterviewPrepView(
                            accent: accent, agent: agent,
                            onConfigureProvider: onConfigureProvider
                        )
                    }
                }
            }
            .sphereCard()
        }
    }

    private var skillsList: some View {
        CRUDListScreen(
            title: uiString("Skills"),
            items: store.careerSkills,
            emptyTitle: uiString("No skills tracked"),
            emptySystemImage: "star",
            addSheet: { AddCareerSkillSheet { s in Task { try? await store.addSkill(s) } } },
            row: { skill in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name).font(.body.weight(.medium))
                        Text(skill.category).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(repeating: "●", count: skill.level)
                        + String(repeating: "○", count: max(5 - skill.level, 0)))
                        .font(.caption).foregroundStyle(accent)
                }
            },
            onDelete: { s in Task { try? await store.removeSkill(id: s.id) } },
            onRestore: { s in Task { try? await store.addSkill(s) } }
        )
    }

    private var salaryList: some View {
        CRUDListScreen(
            title: uiString("Salary history"),
            items: store.salaryHistory,
            emptyTitle: uiString("No entries"),
            emptySystemImage: "banknote",
            addSheet: { AddSalarySheet { e in Task { try? await store.addSalary(e) } } },
            row: { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.0f", entry.amount)).font(.body.weight(.medium))
                        if !entry.role.isEmpty || !entry.company.isEmpty {
                            Text([entry.role, entry.company].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(entry.date, format: .dateTime.month().year())
                        .font(.caption).foregroundStyle(.secondary)
                }
            },
            onDelete: { e in Task { try? await store.removeSalary(id: e.id) } },
            onRestore: { e in Task { try? await store.addSalary(e) } }
        )
    }

    private var goalsList: some View {
        CRUDListScreen(
            title: uiString("Career goals"),
            items: store.careerGoals,
            emptyTitle: uiString("No career goals"),
            emptySystemImage: "target",
            addSheet: { AddCareerGoalSheet { g in Task { try? await store.addCareerGoal(g) } } },
            row: { goal in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(goal.title).font(.body.weight(.medium))
                        Spacer()
                        Text(goal.status.label).font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(goal.progressPercent) / 100).tint(accent)
                }
            },
            onDelete: { g in Task { try? await store.removeCareerGoal(id: g.id) } },
            onRestore: { g in Task { try? await store.addCareerGoal(g) } }
        )
    }

    private var oneOnOnesList: some View {
        CRUDListScreen(
            title: uiString("1:1 notes"),
            items: store.oneOnOnes,
            emptyTitle: uiString("No notes yet"),
            emptySystemImage: "person.2",
            addSheet: { AddOneOnOneSheet { n in Task { try? await store.addOneOnOne(n) } } },
            row: { note in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(note.person).font(.body.weight(.medium))
                        Spacer()
                        Text(note.date, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                    if !note.talkingPoints.isEmpty {
                        Text(ui: "Next: \(note.talkingPoints.joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            },
            onDelete: { n in Task { try? await store.removeOneOnOne(id: n.id) } },
            onRestore: { n in Task { try? await store.addOneOnOne(n) } }
        )
    }

    private var bragDocumentView: some View {
        let text = store.bragDocument()
        return ScrollView {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(Text(ui: "Brag document"))
        .toolbar {
            ShareLink(item: text)
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

    private func statColumn(_ title: LocalizedStringKey, value: Int, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(ui: title).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.title3.weight(.bold)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui: "Tasks").font(.title3.weight(.semibold))
            if store.openTasks.isEmpty {
                Text(ui: "All clear — add a task or tell your agent.")
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
                                Text(ui: "· due \(dueDate, style: .date)")
                                    .foregroundStyle(task.isOverdue() ? .red : .secondary)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    // MARK: - Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui: "Active Projects").font(.title3.weight(.semibold))
            if store.activeProjects.isEmpty {
                Text(ui: "No active projects.")
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
                            Text(ui: days >= 0 ? "\(days) d left" : "\(-days) d over")
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
            Text(ui: "Interviews").font(.title3.weight(.semibold))
            if store.interviews.isEmpty {
                Text(ui: "No applications tracked.")
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
                            Button {
                                Task { try? await store.setInterviewStatus(id: interview.id, status: status) }
                            } label: {
                                Text("\(status.emoji) \(status.label)")
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            Task { try? await store.removeInterview(id: interview.id) }
                        } label: {
                            Text(ui: "Delete")
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
            Text(ui: "Achievements").font(.title3.weight(.semibold))
            if store.achievements.isEmpty {
                Text(ui: "Log a win worth remembering.")
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
                        Label { Text(ui: "Delete") } icon: { Image(systemName: "trash") }
                    }
                }
            }
        }
    }

    // MARK: - Network

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ui: "Network").font(.title3.weight(.semibold))
                Spacer()
                if !store.staleContacts().isEmpty {
                    Text(ui: "\(store.staleContacts().count) to reconnect")
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
                        Text(ui: contact.lastContact == nil ? "Reach out" : "\(contact.daysSinceContact())d")
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
                        Label { Text(ui: "Delete") } icon: { Image(systemName: "trash") }
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
                TextField(text: $title) { Text(ui: "Task title") }
                TextField(text: $project) { Text(ui: "Project (optional)") }
                Picker(selection: $priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Text("\(priority.emoji) \(priority.label)").tag(priority)
                    }
                } label: {
                    Text(ui: "Priority")
                }
                Toggle(isOn: $hasDueDate) { Text(ui: "Due date") }
                if hasDueDate {
                    DatePicker(selection: $dueDate, displayedComponents: .date) { Text(ui: "Due") }
                }
            }
            .navigationTitle(Text(ui: "New Task"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(CareerTask(
                            id: CareerTask.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            project: project.trimmingCharacters(in: .whitespaces),
                            priority: priority,
                            dueDate: hasDueDate ? dueDate : nil,
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

struct AddAchievementSheet: View {
    let onAdd: (Achievement) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var impact = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $title) { Text(ui: "Achievement") }
                TextField(text: $impact) { Text(ui: "Impact (optional)") }
                DatePicker(selection: $date, displayedComponents: .date) { Text(ui: "Date") }
            }
            .navigationTitle(Text(ui: "Log Achievement"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(Achievement(
                            id: Achievement.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            date: date,
                            impact: impact.trimmingCharacters(in: .whitespaces)
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
                TextField(text: $name) { Text(ui: "Name") }
                TextField(text: $role) { Text(ui: "Role") }
                TextField(text: $company) { Text(ui: "Company") }
                TextField(text: $note) { Text(ui: "Note") }
            }
            .navigationTitle(Text(ui: "Add Contact"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(NetworkContact(
                            id: NetworkContact.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            role: role.trimmingCharacters(in: .whitespaces),
                            company: company.trimmingCharacters(in: .whitespaces),
                            note: note.trimmingCharacters(in: .whitespaces)
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

struct AddInterviewSheet: View {
    let onAdd: (Interview) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var company = ""
    @State private var position = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $company) { Text(ui: "Company") }
                TextField(text: $position) { Text(ui: "Position") }
            }
            .navigationTitle(Text(ui: "New Application"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(Interview(
                            id: Interview.newID(),
                            company: company.trimmingCharacters(in: .whitespaces),
                            position: position.trimmingCharacters(in: .whitespaces),
                            appliedDate: Date()
                        ))
                        dismiss()
                    } label: {
                        Text(ui: "Add")
                    }
                    .disabled(company.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddCareerSkillSheet: View {
    let onAdd: (CareerSkill) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = "General"
    @State private var level = 3

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $name) { Text(ui: "Skill") }
                TextField(text: $category) { Text(ui: "Category") }
                Stepper(value: $level, in: 1...5) {
                    Text(ui: "Level: \(level)/5")
                }
            }
            .navigationTitle(Text(ui: "Add Skill"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(CareerSkill(
                            id: CareerSkill.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            category: category.trimmingCharacters(in: .whitespaces).isEmpty
                                ? "General" : category.trimmingCharacters(in: .whitespaces),
                            level: level
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

struct AddSalarySheet: View {
    let onAdd: (SalaryEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var role = ""
    @State private var company = ""
    @State private var date = Date()

    private var amount: Double? { Double(amountText.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $amountText) { Text(ui: "Amount") }
                TextField(text: $role) { Text(ui: "Role") }
                TextField(text: $company) { Text(ui: "Company") }
                DatePicker(selection: $date, displayedComponents: .date) { Text(ui: "Date") }
            }
            .navigationTitle(Text(ui: "Add Salary"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(SalaryEntry(
                            id: SalaryEntry.newID(),
                            amount: amount ?? 0,
                            role: role.trimmingCharacters(in: .whitespaces),
                            company: company.trimmingCharacters(in: .whitespaces),
                            date: date
                        ))
                        dismiss()
                    } label: {
                        Text(ui: "Add")
                    }
                    .disabled(amount == nil)
                }
            }
        }
    }
}

struct AddCareerGoalSheet: View {
    let onAdd: (CareerGoal) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var progress = 0.0

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $title) { Text(ui: "Goal (e.g. Become a staff engineer)") }
                VStack(alignment: .leading) {
                    Text(ui: "Progress: \(Int(progress))%")
                    Slider(value: $progress, in: 0...100, step: 5)
                }
            }
            .navigationTitle(Text(ui: "Add Goal"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(CareerGoal(
                            id: CareerGoal.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            progressPercent: Int(progress)
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

struct AddOneOnOneSheet: View {
    let onAdd: (OneOnOne) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var person = ""
    @State private var role = ""
    @State private var notes = ""
    @State private var talkingPoints = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $person) { Text(ui: "Person") }
                TextField(text: $role) { Text(ui: "Role (e.g. Manager)") }
                TextField(text: $notes, axis: .vertical) { Text(ui: "Notes") }
                    .lineLimit(2...5)
                TextField(text: $talkingPoints, axis: .vertical) {
                    Text(ui: "Talking points (comma-separated)")
                }
            }
            .navigationTitle(Text(ui: "Add 1:1 Note"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let points = talkingPoints
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        onAdd(OneOnOne(
                            id: OneOnOne.newID(),
                            person: person.trimmingCharacters(in: .whitespaces),
                            role: role.trimmingCharacters(in: .whitespaces),
                            date: Date(),
                            notes: notes.trimmingCharacters(in: .whitespaces),
                            talkingPoints: points
                        ))
                        dismiss()
                    } label: {
                        Text(ui: "Add")
                    }
                    .disabled(person.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Paste a role and job description → the assistant drafts tailored interview
/// questions (EXPANSION_PLAN §4.4).
struct InterviewPrepView: View {
    let accent: Color
    var agent: AgentService?
    var onConfigureProvider: (() -> Void)?

    @State private var role = ""
    @State private var jobDescription = ""
    @State private var showingResult = false

    private var canGenerate: Bool {
        !jobDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField(text: $role) { Text(ui: "e.g. Senior iOS Engineer") }
            } header: {
                Text(ui: "Role")
            }
            Section {
                TextField(text: $jobDescription, axis: .vertical) { Text(ui: "Paste the posting here") }
                    .lineLimit(4...12)
            } header: {
                Text(ui: "Job description")
            }
            Section {
                Button {
                    showingResult = true
                } label: {
                    Label { Text(ui: "Get likely questions") } icon: { Image(systemName: "sparkles") }
                }
                .disabled(!canGenerate)
            } footer: {
                Text(ui: "The assistant drafts questions tailored to this description. Nothing is sent anywhere but your chosen assistant.")
            }
        }
        .navigationTitle(Text(ui: "Interview prep"))
        .sheet(isPresented: $showingResult) {
            AgentResultSheet(
                title: uiString("Likely questions"),
                subtitle: role.isEmpty ? nil : role,
                systemImage: "person.crop.rectangle.badge.plus",
                tint: accent,
                agent: agent,
                task: .interviewQuestions(role: role, jobDescription: jobDescription),
                onConfigureProvider: onConfigureProvider
            )
        }
    }
}

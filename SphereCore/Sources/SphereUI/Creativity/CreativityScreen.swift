import SwiftUI
import SphereCore

public struct CreativityScreen: View {
    private let store: CreativityStore
    @State private var showingAddProject = false
    @State private var showingSession = false
    @State private var newIdea = ""

    private let accent = SphereTheme.accent(for: .creativity)

    public init(store: CreativityStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.projects.isEmpty && store.recentIdeas.isEmpty {
                    EmptyStateCard(
                        emoji: "🎨",
                        accent: accent,
                        title: uiString("Start your Creativity sphere"),
                        message: uiString("Capture the idea you keep meaning to start, or the project you're already circling."),
                        buttonLabel: uiString("Add your first project")
                    ) {
                        showingAddProject = true
                    }
                }
                momentumCard
                ideaCaptureCard
                projectSection("In Progress", projects: store.inProgress, empty: "No active projects — start with an idea below.")
                if !store.ideaBacklog.isEmpty {
                    projectSection("Idea Backlog", projects: store.ideaBacklog, empty: "")
                }
                if !store.completed.isEmpty {
                    completedSection
                }
                ideasSection
                moreSection
            }
            .padding()
        }
        .navigationTitle(Text(ui: "Creativity"))
        .toolbar {
            Button {
                showingAddProject = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddProject) {
            AddCreativeProjectSheet { project in
                Task { try? await store.add(project) }
            }
        }
        .sheet(isPresented: $showingSession) {
            CreativeSessionSheet(projects: store.projects, accent: accent) { projectId, minutes in
                Task { try? await store.logSession(projectId: projectId, minutes: minutes) }
            }
        }
        .task {
            try? await store.load()
        }
    }

    // MARK: - Momentum (work sessions)

    private var momentumCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label { Text(ui: "Momentum") } icon: { Image(systemName: "flame.fill") }
                    .font(.headline).foregroundStyle(accent)
                Spacer()
                Text("\(store.minutesThisWeek()) min this week")
                    .font(.subheadline.weight(.semibold))
            }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(store.weeklyMinutes().enumerated()), id: \.offset) { _, minutes in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(minutes > 0 ? accent : Color.secondary.opacity(0.15))
                        .frame(height: max(CGFloat(minutes) / 3, 4))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 44)
            Button {
                showingSession = true
            } label: {
                Label { Text(ui: "Log a work session") } icon: { Image(systemName: "timer") }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(store.projects.isEmpty)
        }
        .sphereCard()
    }

    // MARK: - More (portfolio)

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui: "More").font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                MoreLink(uiString("Portfolio"), systemImage: "photo.stack.fill",
                         count: store.portfolio.isEmpty ? nil : store.portfolio.count) { portfolioList }
            }
            .sphereCard()
        }
    }

    private var portfolioList: some View {
        CRUDListScreen(
            title: uiString("Portfolio"),
            items: store.portfolio,
            emptyTitle: uiString("No finished work yet"),
            emptySystemImage: "photo.stack",
            addSheet: { AddPortfolioSheet { item in Task { try? await store.addPortfolioItem(item) } } },
            row: { item in
                HStack(spacing: 10) {
                    Text(item.type.emoji)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.body.weight(.medium))
                        if !item.url.isEmpty {
                            Text(item.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Text(item.date, format: .dateTime.month().year())
                        .font(.caption).foregroundStyle(.secondary)
                }
            },
            onDelete: { item in Task { try? await store.removePortfolioItem(id: item.id) } },
            onRestore: { item in Task { try? await store.addPortfolioItem(item) } }
        )
    }

    // MARK: - Idea capture

    private var ideaCaptureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ui: "💡 Capture an idea").font(.headline)
            HStack {
                TextField(text: $newIdea) { Text(ui: "A melody, a story, a shot…") }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(captureIdea)
                Button(action: captureIdea) {
                    Image(systemName: "arrow.down.doc.fill").foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .disabled(newIdea.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    private func captureIdea() {
        let content = newIdea.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return }
        newIdea = ""
        Task { try? await store.addIdea(content) }
    }

    // MARK: - Projects

    private func projectSection(
        _ title: LocalizedStringKey, projects: [CreativeProject], empty: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui: title).font(.title3.weight(.semibold))
            if projects.isEmpty {
                Text(ui: empty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(projects) { project in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(project.type.emoji)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.title).font(.body.weight(.medium))
                            if let lastWorkedOn = project.lastWorkedOn {
                                Text("Last worked \(lastWorkedOn, style: .relative) ago")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Menu {
                            Button {
                                Task { try? await store.setProgress(id: project.id, percent: project.progressPercent + 10) }
                            } label: {
                                Text(ui: "+10% progress")
                            }
                            Button(role: .destructive) {
                                Task { try? await store.remove(id: project.id) }
                            } label: {
                                Text(ui: "Delete")
                            }
                        } label: {
                            Image(systemName: "ellipsis").foregroundStyle(.secondary)
                        }
                    }
                    ProgressView(value: Double(project.progressPercent), total: 100)
                        .tint(accent)
                    HStack {
                        Text("\(project.progressPercent)%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                        Spacer()
                        if !project.collaborators.isEmpty {
                            Text("with \(project.collaborators.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .sphereCard()
            }
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui: "Completed").font(.title3.weight(.semibold))
            ForEach(store.completed) { project in
                HStack {
                    Text(project.type.emoji)
                    Text(project.title).strikethrough()
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .sphereCard()
            }
        }
    }

    // MARK: - Ideas

    private var ideasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui: "Ideas").font(.title3.weight(.semibold))
            if store.recentIdeas.isEmpty {
                Text(ui: "Captured ideas will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(store.recentIdeas) { idea in
                HStack(alignment: .top, spacing: 12) {
                    Text("💡")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(idea.content).font(.body)
                        HStack {
                            Text(idea.tag)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(accent.opacity(0.12), in: Capsule())
                                .foregroundStyle(accent)
                            Text(idea.date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        Task { try? await store.removeIdea(id: idea.id) }
                    } label: {
                        Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .sphereCard()
            }
        }
    }
}

struct AddCreativeProjectSheet: View {
    let onAdd: (CreativeProject) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var type = CreativeType.writing
    @State private var isIdea = false

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $title) { Text(ui: "Title") }
                TextField(text: $details) { Text(ui: "Description (optional)") }
                Picker("Type", selection: $type) {
                    ForEach(CreativeType.allCases, id: \.self) { type in
                        Text("\(type.emoji) \(type.label)").tag(type)
                    }
                }
                Toggle("Just an idea for now", isOn: $isIdea)
            }
            .navigationTitle(Text(ui: "New Project"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(CreativeProject(
                            id: CreativeProject.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            description: details,
                            type: type,
                            status: isIdea ? .idea : .inProgress,
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

/// A count-up session timer: pick a project, start, and the elapsed minutes
/// log on stop — momentum you can feel.
struct CreativeSessionSheet: View {
    let projects: [CreativeProject]
    let accent: Color
    let onLog: (String, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var projectId = ""
    @State private var elapsed = 0
    @State private var running = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Picker("Project", selection: $projectId) {
                    ForEach(projects) { project in
                        Text("\(project.type.emoji) \(project.title)").tag(project.id)
                    }
                }
                .pickerStyle(.menu)

                Text(timeString(elapsed))
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundStyle(running ? accent : .primary)

                Button {
                    if running { finish() } else { running = true }
                } label: {
                    running ? Text(ui: "Finish & log") : Text(ui: "Start")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(projectId.isEmpty)
            }
            .padding()
            .navigationTitle(Text(ui: "Work session"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Text(ui: "Cancel") } }
            }
            .onAppear { if projectId.isEmpty { projectId = projects.first?.id ?? "" } }
            .task(id: running) {
                guard running else { return }
                while running {
                    try? await Task.sleep(for: .seconds(1))
                    if !running { return }
                    elapsed += 1
                }
            }
        }
    }

    private func finish() {
        running = false
        onLog(projectId, max(elapsed / 60, 1))
        dismiss()
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct AddPortfolioSheet: View {
    let onAdd: (PortfolioItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var type = CreativeType.writing
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $title) { Text(ui: "Title") }
                Picker("Type", selection: $type) {
                    ForEach(CreativeType.allCases, id: \.self) { t in
                        Text("\(t.emoji) \(t.label)").tag(t)
                    }
                }
                TextField(text: $url) { Text(ui: "Link (optional)") }
            }
            .navigationTitle(Text(ui: "Add to Portfolio"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Text(ui: "Cancel") } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(PortfolioItem(
                            id: PortfolioItem.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            type: type,
                            url: url.trimmingCharacters(in: .whitespaces),
                            date: Date()
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

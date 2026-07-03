import SwiftUI
import SphereCore

public struct CreativityScreen: View {
    private let store: CreativityStore
    @State private var showingAddProject = false
    @State private var newIdea = ""

    private let accent = SphereTheme.accent(for: .creativity)

    public init(store: CreativityStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ideaCaptureCard
                projectSection("In Progress", projects: store.inProgress, empty: "No active projects — start with an idea below.")
                if !store.ideaBacklog.isEmpty {
                    projectSection("Idea Backlog", projects: store.ideaBacklog, empty: "")
                }
                if !store.completed.isEmpty {
                    completedSection
                }
                ideasSection
            }
            .padding()
        }
        .navigationTitle("Creativity")
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
        .task {
            try? await store.load()
        }
    }

    // MARK: - Idea capture

    private var ideaCaptureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("💡 Capture an idea").font(.headline)
            HStack {
                TextField("A melody, a story, a shot…", text: $newIdea)
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
        _ title: String, projects: [CreativeProject], empty: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            if projects.isEmpty && !empty.isEmpty {
                Text(empty)
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
                            Button("+10% progress") {
                                Task { try? await store.setProgress(id: project.id, percent: project.progressPercent + 10) }
                            }
                            Button("Delete", role: .destructive) {
                                Task { try? await store.remove(id: project.id) }
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
            Text("Completed").font(.title3.weight(.semibold))
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
            Text("Ideas").font(.title3.weight(.semibold))
            if store.recentIdeas.isEmpty {
                Text("Captured ideas will appear here.")
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
                TextField("Title", text: $title)
                TextField("Description (optional)", text: $details)
                Picker("Type", selection: $type) {
                    ForEach(CreativeType.allCases, id: \.self) { type in
                        Text("\(type.emoji) \(type.label)").tag(type)
                    }
                }
                Toggle("Just an idea for now", isOn: $isIdea)
            }
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(CreativeProject(
                            id: CreativeProject.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            description: details,
                            type: type,
                            status: isIdea ? .idea : .inProgress,
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

import SwiftUI
import SphereCore

public struct LearningScreen: View {
    private let store: LearningStore
    @State private var showingAddBook = false
    @State private var showingAddSkill = false

    private let accent = SphereTheme.accent(for: .learning)

    public init(store: LearningStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                bookSection("Currently Reading", books: store.reading, empty: "Nothing in progress — pick one from the queue.")
                bookSection("Queue", books: store.queue, empty: "Queue is empty.")
                if !store.completed.isEmpty {
                    completedSection
                }
                skillsSection
            }
            .padding()
        }
        .navigationTitle("Learning")
        .toolbar {
            Menu {
                Button("Add Book") { showingAddBook = true }
                Button("Add Skill") { showingAddSkill = true }
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddBook) {
            AddBookSheet { book in
                Task { try? await store.add(book) }
            }
        }
        .sheet(isPresented: $showingAddSkill) {
            AddSkillSheet { skill in
                Task { try? await store.addSkill(skill) }
            }
        }
        .task {
            try? await store.load()
        }
    }

    // MARK: - Books

    private func bookSection(_ title: String, books: [Book], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            if books.isEmpty {
                Text(empty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(books) { book in
                BookCard(book: book, accent: accent) { page in
                    Task { try? await store.setPage(id: book.id, page: page) }
                } onComplete: {
                    Task { try? await store.markComplete(id: book.id) }
                } onDelete: {
                    Task { try? await store.remove(id: book.id) }
                }
            }
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Completed").font(.title3.weight(.semibold))
            ForEach(store.completed) { book in
                HStack {
                    Text(book.emoji)
                    Text(book.title).strikethrough()
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .sphereCard()
            }
        }
    }

    // MARK: - Skills

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Skills").font(.title3.weight(.semibold))
            if store.skills.isEmpty {
                Text("Track a skill you're learning.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(store.skillCategories, id: \.self) { category in
                VStack(alignment: .leading, spacing: 8) {
                    Text(category)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(store.skills.filter { $0.category == category }) { skill in
                        SkillRow(skill: skill, accent: accent) {
                            Task { try? await store.levelUp(id: skill.id) }
                        } onLevelDown: {
                            Task { try? await store.levelDown(id: skill.id) }
                        }
                    }
                }
                .sphereCard()
            }
        }
    }
}

struct BookCard: View {
    let book: Book
    let accent: Color
    let onSetPage: (Int) -> Void
    let onComplete: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(book.emoji)
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).font(.body.weight(.medium))
                    if !book.author.isEmpty {
                        Text(book.author).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button("+10 pages") { onSetPage(book.currentPage + 10) }
                    Button("Mark complete", action: onComplete)
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(.secondary)
                }
            }
            if book.totalPages > 0 {
                ProgressView(value: book.progress).tint(accent)
                Text("p. \(book.currentPage) of \(book.totalPages) · \(Int(book.progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sphereCard()
    }
}

struct SkillRow: View {
    let skill: LearningSkill
    let accent: Color
    let onLevelUp: () -> Void
    let onLevelDown: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name).font(.body.weight(.medium))
                Text(skill.status.label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(1...LearningSkill.maxLevel, id: \.self) { dot in
                    Circle()
                        .fill(dot <= skill.level ? accent : Color.secondary.opacity(0.25))
                        .frame(width: 8, height: 8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onLevelUp)
            .onLongPressGesture(perform: onLevelDown)
        }
    }
}

struct AddBookSheet: View {
    let onAdd: (Book) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var author = ""
    @State private var totalPagesText = ""
    @State private var startReading = true

    private var totalPages: Int? {
        Int(totalPagesText)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Author", text: $author)
                TextField("Total pages", text: $totalPagesText)
                Toggle("Start reading now", isOn: $startReading)
            }
            .navigationTitle("Add Book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(Book(
                            id: Book.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            author: author.trimmingCharacters(in: .whitespaces),
                            totalPages: totalPages ?? 0,
                            status: startReading ? .reading : .wantToRead
                        ))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddSkillSheet: View {
    let onAdd: (LearningSkill) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = "General"
    @State private var status = SkillStatus.learning

    var body: some View {
        NavigationStack {
            Form {
                TextField("Skill", text: $name)
                TextField("Category", text: $category)
                Picker("Status", selection: $status) {
                    ForEach(SkillStatus.allCases, id: \.self) { status in
                        Text(status.label).tag(status)
                    }
                }
            }
            .navigationTitle("Add Skill")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(LearningSkill(
                            id: LearningSkill.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            category: category.isEmpty ? "General" : category,
                            status: status
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

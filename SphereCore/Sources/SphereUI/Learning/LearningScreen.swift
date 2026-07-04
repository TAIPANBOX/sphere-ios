import SwiftUI
import SphereCore

public struct LearningScreen: View {
    private let store: LearningStore
    @State private var showingAddBook = false
    @State private var showingAddSkill = false
    @State private var showingReview = false

    private let accent = SphereTheme.accent(for: .learning)

    public init(store: LearningStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !store.flashcards.isEmpty {
                    flashcardsCard
                }
                bookSection("Currently Reading", books: store.reading, empty: "Nothing in progress — pick one from the queue.")
                bookSection("Queue", books: store.queue, empty: "Queue is empty.")
                if !store.completed.isEmpty {
                    completedSection
                }
                skillsSection
                moreSection
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
        .sheet(isPresented: $showingReview) {
            FlashcardReviewSheet(store: store, accent: accent)
        }
        .task {
            try? await store.load()
        }
    }

    // MARK: - Flashcards (spaced repetition)

    private var flashcardsCard: some View {
        let due = store.dueFlashcards().count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Flashcards", systemImage: "rectangle.on.rectangle.angled")
                    .font(.headline)
                    .foregroundStyle(accent)
                Spacer()
                Text("\(store.flashcards.count) cards")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if due > 0 {
                Button {
                    showingReview = true
                } label: {
                    Text("Review \(due) due").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            } else {
                Text("All caught up — nothing due right now.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .sphereCard()
    }

    // MARK: - More (courses, languages, queue, flashcards)

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("More").font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                MoreLink("Courses", systemImage: "graduationcap.fill",
                         count: store.courses.isEmpty ? nil : store.courses.count) { coursesList }
                Divider().padding(.leading, 38)
                MoreLink("Languages", systemImage: "character.bubble.fill",
                         count: store.languages.isEmpty ? nil : store.languages.count) { languagesList }
                Divider().padding(.leading, 38)
                MoreLink("Read / watch later", systemImage: "bookmark.fill",
                         count: store.pendingQueue.isEmpty ? nil : store.pendingQueue.count) { queueList }
                Divider().padding(.leading, 38)
                MoreLink("Manage flashcards", systemImage: "rectangle.on.rectangle.angled",
                         count: store.flashcards.isEmpty ? nil : store.flashcards.count) { flashcardsList }
            }
            .sphereCard()
        }
    }

    private var coursesList: some View {
        CRUDListScreen(
            title: "Courses",
            items: store.courses,
            emptyTitle: "No courses tracked",
            emptySystemImage: "graduationcap",
            addSheet: { AddCourseSheet { course in Task { try? await store.addCourse(course) } } },
            row: { course in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(course.name).font(.body.weight(.medium))
                        Spacer()
                        Text("\(course.progressPercent)%").font(.caption).foregroundStyle(.secondary)
                    }
                    if !course.provider.isEmpty {
                        Text(course.provider).font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(course.progressPercent) / 100).tint(accent)
                }
            },
            onDelete: { course in Task { try? await store.removeCourse(id: course.id) } },
            onRestore: { course in Task { try? await store.addCourse(course) } }
        )
    }

    private var languagesList: some View {
        CRUDListScreen(
            title: "Languages",
            items: store.languages,
            emptyTitle: "No languages tracked",
            emptySystemImage: "character.bubble",
            addSheet: { AddLanguageSheet { lang in Task { try? await store.addLanguage(lang) } } },
            row: { lang in
                HStack {
                    Text(lang.name).font(.body.weight(.medium))
                    Spacer()
                    Text(lang.level).font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                }
            },
            onDelete: { lang in Task { try? await store.removeLanguage(id: lang.id) } },
            onRestore: { lang in Task { try? await store.addLanguage(lang) } }
        )
    }

    private var queueList: some View {
        CRUDListScreen(
            title: "Read / watch later",
            items: store.queueItems,
            emptyTitle: "Queue is empty",
            emptySystemImage: "bookmark",
            addSheet: { AddQueueItemSheet { item in Task { try? await store.addQueueItem(item) } } },
            row: { item in
                Button {
                    Task { try? await store.toggleQueueItem(id: item.id) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.done ? .green : .secondary)
                        Text(item.kind.emoji)
                        Text(item.title)
                            .strikethrough(item.done)
                            .foregroundStyle(item.done ? .secondary : .primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            },
            onDelete: { item in Task { try? await store.removeQueueItem(id: item.id) } },
            onRestore: { item in Task { try? await store.addQueueItem(item) } }
        )
    }

    private var flashcardsList: some View {
        CRUDListScreen(
            title: "Flashcards",
            items: store.flashcards,
            emptyTitle: "No flashcards yet",
            emptySystemImage: "rectangle.on.rectangle.angled",
            addSheet: { AddFlashcardSheet { card in Task { try? await store.addFlashcard(card) } } },
            row: { card in
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.front).font(.body.weight(.medium))
                    Text(card.back).font(.caption).foregroundStyle(.secondary)
                }
            },
            onDelete: { card in Task { try? await store.removeFlashcard(id: card.id) } },
            onRestore: { card in Task { try? await store.addFlashcard(card) } }
        )
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

struct FlashcardReviewSheet: View {
    let store: LearningStore
    let accent: Color
    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let card = store.dueFlashcards().first {
                    Spacer()
                    VStack(spacing: 16) {
                        Text(card.front)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                        if revealed {
                            Divider()
                            Text(card.back)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(28)
                    .sphereCard()
                    Spacer()
                    if revealed {
                        HStack(spacing: 10) {
                            gradeButton("Forgot", .forgot, .red, card.id)
                            gradeButton("Good", .good, accent, card.id)
                            gradeButton("Easy", .easy, .green, card.id)
                        }
                    } else {
                        Button {
                            revealed = true
                        } label: {
                            Text("Show answer").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                    }
                } else {
                    Spacer()
                    ContentUnavailableView(
                        "All caught up",
                        systemImage: "checkmark.seal.fill",
                        description: Text("No cards due right now — come back later.")
                    )
                    Spacer()
                }
            }
            .padding()
            .navigationTitle("Review")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func gradeButton(_ title: String, _ grade: ReviewGrade, _ tint: Color, _ id: String) -> some View {
        Button {
            Task {
                try? await store.reviewFlashcard(id: id, grade: grade)
                revealed = false
            }
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }
}

struct AddCourseSheet: View {
    let onAdd: (Course) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var provider = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Course name", text: $name)
                TextField("Provider (e.g. Coursera)", text: $provider)
            }
            .navigationTitle("Add Course")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(Course(
                            id: Course.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            provider: provider.trimmingCharacters(in: .whitespaces)
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddLanguageSheet: View {
    let onAdd: (LanguageStudy) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var level = "A1"

    private let levels = ["A1", "A2", "B1", "B2", "C1", "C2", "Native"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Language", text: $name)
                Picker("Level", selection: $level) {
                    ForEach(levels, id: \.self) { Text($0).tag($0) }
                }
            }
            .navigationTitle("Add Language")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(LanguageStudy(
                            id: LanguageStudy.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            level: level
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddQueueItemSheet: View {
    let onAdd: (LearningQueueItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind = QueueKind.article

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                Picker("Kind", selection: $kind) {
                    ForEach(QueueKind.allCases, id: \.self) { k in
                        Text("\(k.emoji) \(k.rawValue.capitalized)").tag(k)
                    }
                }
            }
            .navigationTitle("Add to Queue")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(LearningQueueItem(
                            id: LearningQueueItem.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            kind: kind,
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

struct AddFlashcardSheet: View {
    let onAdd: (Flashcard) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var deck = "General"
    @State private var front = ""
    @State private var back = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Deck", text: $deck)
                TextField("Front (question)", text: $front, axis: .vertical)
                TextField("Back (answer)", text: $back, axis: .vertical)
            }
            .navigationTitle("Add Flashcard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(Flashcard(
                            id: Flashcard.newID(),
                            deck: deck.trimmingCharacters(in: .whitespaces),
                            front: front.trimmingCharacters(in: .whitespaces),
                            back: back.trimmingCharacters(in: .whitespaces),
                            dueDate: Date()
                        ))
                        dismiss()
                    }
                    .disabled(front.trimmingCharacters(in: .whitespaces).isEmpty
                        || back.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

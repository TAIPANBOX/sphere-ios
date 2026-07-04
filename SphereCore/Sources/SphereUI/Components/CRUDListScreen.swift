import SwiftUI

/// Generic drill-down list used by every sphere's secondary lists, so 40+
/// parity lists share one implementation: rows + swipe-to-delete + an add
/// sheet + a friendly empty state with a one-tap "add first" action.
///
/// The screen-anatomy rule (docs/EXPANSION_PLAN §1.3): a sphere's main screen
/// keeps only its hero + up to three primary sections inline, and links out
/// to a `CRUDListScreen` for every secondary list.
public struct CRUDListScreen<Item: Identifiable, Row: View, AddSheet: View>: View {
    private let title: String
    private let items: [Item]
    private let emptyTitle: String
    private let emptySystemImage: String
    private let addLabel: String
    private let rowContent: (Item) -> Row
    private let addSheet: () -> AddSheet
    private let onDelete: (Item) -> Void
    private let onRestore: ((Item) -> Void)?

    @State private var showingAdd = false
    @State private var recentlyDeleted: Item?

    public init(
        title: String,
        items: [Item],
        emptyTitle: String,
        emptySystemImage: String = "tray",
        addLabel: String = "Add",
        @ViewBuilder addSheet: @escaping () -> AddSheet,
        @ViewBuilder row: @escaping (Item) -> Row,
        onDelete: @escaping (Item) -> Void,
        onRestore: ((Item) -> Void)? = nil
    ) {
        self.title = title
        self.items = items
        self.emptyTitle = emptyTitle
        self.emptySystemImage = emptySystemImage
        self.addLabel = addLabel
        self.rowContent = row
        self.addSheet = addSheet
        self.onDelete = onDelete
        self.onRestore = onRestore
    }

    public var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: emptySystemImage)
                } actions: {
                    Button(addLabel) { showingAdd = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(items) { item in rowContent(item) }
                        .onDelete { offsets in
                            // Plain loop: the map/forEach chain trips typed-throws
                            // checking on some Swift 6.x compilers.
                            for offset in offsets { delete(items[offset]) }
                        }
                }
            }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            Button { showingAdd = true } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $showingAdd) { addSheet() }
        .overlay(alignment: .bottom) { undoBar }
        .animation(.snappy, value: recentlyDeleted?.id)
    }

    @ViewBuilder
    private var undoBar: some View {
        if let item = recentlyDeleted, let onRestore {
            HStack(spacing: 12) {
                Text("Deleted").font(.subheadline)
                Spacer()
                Button("Undo") {
                    onRestore(item)
                    recentlyDeleted = nil
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func delete(_ item: Item) {
        onDelete(item)
        guard onRestore != nil else { return }
        recentlyDeleted = item
        Task {
            try? await Task.sleep(for: .seconds(4))
            if recentlyDeleted?.id == item.id { recentlyDeleted = nil }
        }
    }
}

/// A tappable "More" row: a labelled `NavigationLink` styled as a card, used
/// on sphere hero screens to link out to `CRUDListScreen` detail pages.
public struct MoreLink<Destination: View>: View {
    private let title: String
    private let systemImage: String
    private let count: Int?
    private let destination: () -> Destination

    public init(
        _ title: String,
        systemImage: String,
        count: Int? = nil,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.systemImage = systemImage
        self.count = count
        self.destination = destination
    }

    public var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 26)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer()
                if let count {
                    Text("\(count)").foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

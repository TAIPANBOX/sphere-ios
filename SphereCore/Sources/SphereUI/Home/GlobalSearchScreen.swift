import SwiftUI
import SphereCore

/// Cross-sphere search: one field over every sphere's records plus Engram
/// memories. Result rows navigate to their sphere via the enclosing
/// NavigationStack's `navigationDestination(for: SphereType.self)`.
public struct GlobalSearchScreen: View {
    private let store: SearchStore
    @State private var query = ""
    @State private var memories: [EngramMemory] = []

    public init(store: SearchStore) { self.store = store }

    private var groups: [(sphere: SphereType, items: [SearchItem])] {
        query.isEmpty ? [] : store.grouped(for: query)
    }

    public var body: some View {
        List {
            if query.isEmpty {
                ContentUnavailableViewCompat(
                    "Search everything",
                    systemImage: "magnifyingglass",
                    description: "Goals, contacts, books, tasks, subscriptions, journal notes and memories — all in one place."
                )
            } else if groups.isEmpty && memories.isEmpty {
                ContentUnavailableViewCompat(
                    "No matches",
                    systemImage: "magnifyingglass",
                    description: "Nothing matches “\(query)” yet."
                )
            } else {
                ForEach(groups, id: \.sphere) { group in
                    Section(group.sphere.rawValue.capitalized) {
                        ForEach(group.items) { item in
                            NavigationLink(value: item.sphere) {
                                resultRow(item)
                            }
                        }
                    }
                }
                if !memories.isEmpty {
                    Section("Memories") {
                        ForEach(memories, id: \.id) { memory in
                            Label(memory.content, systemImage: "brain")
                                .font(.subheadline)
                                .lineLimit(3)
                        }
                    }
                }
            }
        }
        .sphereAnimation(SphereMotion.gentle, value: groups.map(\.items.count))
        .sphereAnimation(SphereMotion.gentle, value: memories.count)
        .navigationTitle("Search")
        .searchableCompat(text: $query, prompt: "Search across Sphere")
        .task(id: query) {
            guard query.count >= 2 else { memories = []; return }
            memories = await store.memories(for: query)
        }
    }

    private func resultRow(_ item: SearchItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(SphereTheme.accent(for: item.sphere))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Cross-platform shims (SphereUI compiles on macOS too)

private struct ContentUnavailableViewCompat: View {
    let title: String
    let systemImage: String
    let description: String

    init(_ title: String, systemImage: String, description: String) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(description).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowSeparator(.hidden)
    }
}

private extension View {
    @ViewBuilder
    func searchableCompat(text: Binding<String>, prompt: String) -> some View {
        #if os(iOS)
        self.searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        #else
        self.searchable(text: text, prompt: prompt)
        #endif
    }
}

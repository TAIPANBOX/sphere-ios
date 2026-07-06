import SwiftUI
import SphereCore

/// Settings "Cloud model" page: pick which OpenRouter model answers cloud
/// chats. A "Recommended" shortlist sits above a searchable full list; the
/// provider default row clears the explicit choice. The selection getter/
/// setter is injected so this SphereUI screen never touches app-target
/// UserDefaults keys directly.
public struct CloudModelsScreen: View {
    private let catalog: OpenRouterModelCatalog
    private let selectedID: () -> String?
    private let setSelectedID: (String?) -> Void

    @State private var models: [CloudModelInfo] = []
    @State private var loading = true
    @State private var query = ""
    @State private var selection: String?

    public init(
        catalog: OpenRouterModelCatalog,
        selectedID: @escaping () -> String?,
        setSelectedID: @escaping (String?) -> Void
    ) {
        self.catalog = catalog
        self.selectedID = selectedID
        self.setSelectedID = setSelectedID
    }

    private var recommended: [CloudModelInfo] {
        OpenRouterModelCatalog.recommended(from: models)
    }

    private var filtered: [CloudModelInfo] {
        guard !query.isEmpty else { return models }
        let needle = query.lowercased()
        return models.filter {
            $0.name.lowercased().contains(needle) || $0.id.lowercased().contains(needle)
        }
    }

    public var body: some View {
        List {
            if loading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading models…")
                        Spacer()
                    }
                }
            }

            Section {
                row(id: nil, name: "Default", subtitle: "Provider's recommended model")
            }

            if !recommended.isEmpty {
                Section("Recommended") {
                    ForEach(recommended) { model in
                        row(model)
                    }
                }
            }

            if !models.isEmpty {
                Section("All models") {
                    ForEach(filtered) { model in
                        row(model)
                    }
                }
            }
        }
        .navigationTitle("Cloud model")
        .searchableCompat(text: $query, prompt: "Search models")
        .task {
            selection = selectedID()
            models = await catalog.load()
            loading = false
        }
    }

    @ViewBuilder
    private func row(_ model: CloudModelInfo) -> some View {
        row(
            id: model.id,
            name: model.name,
            subtitle: subtitle(for: model),
            warnsAboutImages: !model.supportsImages
        )
    }

    @ViewBuilder
    private func row(id: String?, name: String, subtitle: String, warnsAboutImages: Bool = false) -> some View {
        let isSelected = selection == id
        Button {
            selection = id
            setSelectedID(id)
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.body).foregroundStyle(.primary)
                    if let id {
                        Text(id).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    if warnsAboutImages {
                        Text("Photo capture will not work with this model.")
                            .font(.caption2)
                            .foregroundStyle(Color.orange)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(SphereTheme.accent(for: .mindfulness))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func subtitle(for model: CloudModelInfo) -> String {
        var parts: [String] = []
        if let context = model.contextTokens {
            parts.append(contextLabel(context))
        }
        if let prompt = model.promptPricePerMTok, let completion = model.completionPricePerMTok {
            parts.append(String(format: "$%.2f / $%.2f per 1M", prompt, completion))
        }
        if model.supportsImages {
            parts.append("Vision")
        }
        return parts.joined(separator: " · ")
    }

    private func contextLabel(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM context", Double(tokens) / 1_000_000)
        }
        if tokens >= 1_000 {
            return "\(tokens / 1_000)K context"
        }
        return "\(tokens) context"
    }
}

// MARK: - Cross-platform shim (SphereUI compiles on macOS too)

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

import SwiftUI
import SphereCore
import SphereUI

/// Spheres tab: the user's active spheres in their saved order, each with a
/// live one-line stat and progress bar. Tap a row to open the sphere; tap
/// the bubble to chat with its agent. Edit mode enables drag-to-reorder,
/// which persists to the profile.
struct SpheresGridScreen: View {
    let container: AppContainer

    enum Destination: Hashable {
        case screen(SphereType)
        case chat(SphereType)
    }

    @State private var destination: Destination?
    @State private var showingCapture = false
    @AppStorage(Prefs.currency) private var currency = Currency.deviceDefault.rawValue

    private static let emojis: [SphereType: String] = [
        .health: "🫀", .learning: "📚", .career: "💼", .finance: "💰",
        .relationships: "💜", .rest: "🌊", .hobbies: "🎸", .travel: "✈️",
        .mindfulness: "🧘", .creativity: "🎨", .home: "🏡", .goals: "🎯",
    ]

    private var spheres: [SphereType] {
        container.profile.profile.orderedActiveSpheres
    }

    var body: some View {
        List {
            ForEach(spheres, id: \.self) { sphere in
                row(for: sphere)
            }
            .onMove(perform: move)
        }
        .navigationTitle("Spheres")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingCapture = true } label: { Image(systemName: "plus.circle.fill") }
                    .accessibilityLabel("Quick capture")
            }
            ToolbarItem(placement: .topBarLeading) { EditButton() }
        }
        .sheet(isPresented: $showingCapture) {
            QuickCaptureSheet { await container.quickCapture($0) }
        }
        .navigationDestination(item: $destination) { dest in
            switch dest {
            case .screen(let sphere): sphereScreen(sphere)
            case .chat(let sphere): ChatScreen(session: container.chatSession(for: sphere))
            }
        }
    }

    private func row(for sphere: SphereType) -> some View {
        let accent = SphereTheme.accent(for: sphere)
        let stat = container.sphereStat(for: sphere)
        return HStack(spacing: 12) {
            Button {
                destination = .screen(sphere)
            } label: {
                HStack(spacing: 12) {
                    Text(Self.emojis[sphere] ?? "✨").font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(sphere.rawValue.capitalized))
                            .font(.body.weight(.semibold))
                        if !stat.statLine.isEmpty {
                            Text(stat.statLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        ProgressView(value: stat.progress).tint(accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                destination = .chat(sphere)
            } label: {
                Image(systemName: "bubble.left.fill")
                    .foregroundStyle(accent)
            }
            .buttonStyle(.borderless)
        }
    }

    private func move(from source: IndexSet, to offset: Int) {
        var reordered = spheres
        reordered.move(fromOffsets: source, toOffset: offset)
        Task { await container.reorderSpheres(reordered) }
    }

    @ViewBuilder
    private func sphereScreen(_ sphere: SphereType) -> some View {
        SphereRootScreen(sphere: sphere, container: container)
    }
}

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
        .toolbar { EditButton() }
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
                        Text(sphere.rawValue.capitalized).font(.body.weight(.semibold))
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
        switch sphere {
        case .health: HealthScreen(store: container.health, heightCm: container.profile.profile.heightCm)
        case .learning: LearningScreen(store: container.learning)
        case .career: CareerScreen(store: container.career)
        case .finance: FinanceScreen(store: container.finance)
        case .relationships: RelationshipsScreen(store: container.relationships)
        case .rest: RestScreen(store: container.rest, stressLevel: container.mindfulness.todayStress())
        case .hobbies: HobbiesScreen(store: container.hobbies)
        case .travel: TravelScreen(store: container.travel)
        case .mindfulness: MindfulnessScreen(store: container.mindfulness)
        case .creativity: CreativityScreen(store: container.creativity)
        case .home: HomeSphereScreen(store: container.homeSphere)
        case .goals: GoalsScreen(store: container.goals)
        }
    }
}

import SwiftUI
import SphereCore
import SphereUI

/// 2-column grid of the 12 spheres. Tap opens the sphere screen; the chat
/// bubble opens the sphere's agent. (Drag-to-reorder and live stat lines
/// arrive with the full dashboard port.)
struct SpheresGridScreen: View {
    let container: AppContainer

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private var activeSpheres: [SphereType] {
        SphereType.allCases.filter { container.profile.profile.isSphereActive($0) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(activeSpheres, id: \.self) { sphere in
                    NavigationLink {
                        sphereScreen(sphere)
                    } label: {
                        SphereCard(sphere: sphere)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topTrailing) {
                        NavigationLink {
                            ChatScreen(session: container.chatSession(for: sphere))
                        } label: {
                            Image(systemName: "bubble.left.fill")
                                .font(.caption)
                                .foregroundStyle(SphereTheme.accent(for: sphere))
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Spheres")
    }

    @ViewBuilder
    private func sphereScreen(_ sphere: SphereType) -> some View {
        switch sphere {
        case .health: HealthScreen(store: container.health)
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

private struct SphereCard: View {
    let sphere: SphereType

    private static let emojis: [SphereType: String] = [
        .health: "🫀", .learning: "📚", .career: "💼", .finance: "💰",
        .relationships: "💜", .rest: "🌊", .hobbies: "🎸", .travel: "✈️",
        .mindfulness: "🧘", .creativity: "🎨", .home: "🏡", .goals: "🎯",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.emojis[sphere] ?? "✨").font(.system(size: 30))
            Text(sphere.rawValue.capitalized)
                .font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(14)
        .background(
            SphereTheme.accent(for: sphere).opacity(0.1),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

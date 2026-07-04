import SwiftUI
import SphereCore
import SphereUI

/// Maps a `SphereType` to its screen, wiring the extra parameters each screen
/// needs from the container. Shared by the Spheres grid and the Home tab's
/// value-based navigation (`navigationDestination(for: SphereType.self)`) so
/// there is exactly one place that knows how to build a sphere screen.
struct SphereRootScreen: View {
    let sphere: SphereType
    let container: AppContainer
    @AppStorage(Prefs.currency) private var currency = Currency.deviceDefault.rawValue

    var body: some View {
        switch sphere {
        case .health:
            HealthScreen(
                store: container.health,
                heightCm: container.profile.profile.heightCm,
                showsCycle: container.profile.profile.gender == .female
            )
        case .learning:
            LearningScreen(store: container.learning)
        case .career:
            CareerScreen(store: container.career, agent: container.agent)
        case .finance:
            FinanceScreen(store: container.finance, currency: storedCurrency(currency))
        case .relationships:
            RelationshipsScreen(store: container.relationships, agent: container.agent)
        case .rest:
            RestScreen(
                store: container.rest,
                stressLevel: container.mindfulness.todayStress(),
                vacationAllowance: container.profile.profile.vacationDaysPerYear
            )
        case .hobbies:
            HobbiesScreen(store: container.hobbies)
        case .travel:
            TravelScreen(store: container.travel)
        case .mindfulness:
            MindfulnessScreen(store: container.mindfulness)
        case .creativity:
            CreativityScreen(store: container.creativity)
        case .home:
            HomeSphereScreen(store: container.homeSphere)
        case .goals:
            GoalsScreen(store: container.goals, agent: container.agent)
        }
    }
}

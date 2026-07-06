import SwiftUI
import SphereCore
import SphereUI

@main
struct SphereApp: App {
    @State private var container = AppContainer()
    @State private var loaded = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Prefs.theme) private var theme = ThemePreference.system.rawValue

    var body: some Scene {
        WindowGroup {
            LockGate {
                Group {
                    if !loaded {
                        ProgressView()
                    } else if !container.profile.profile.onboarded {
                        OnboardingFlow(container: container)
                    } else {
                        RootView(container: container)
                    }
                }
            }
            .preferredColorScheme(ThemePreference(rawValue: theme)?.colorScheme)
            .task {
                await container.loadAll()
                loaded = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                container.refreshWidget()
                Task {
                    await container.runMemoryMaintenance()
                    await container.refreshReminders()
                }
            } else if phase == .active && loaded {
                // Widget buttons and Siri write to the shared DB while this
                // app instance may be holding stale in-memory stores; reload
                // just the quick-log-affected ones rather than a full loadAll.
                Task {
                    try? await container.health.load()
                    try? await container.mindfulness.load()
                    container.refreshWidget()
                }
            }
        }
    }
}

struct RootView: View {
    let container: AppContainer

    enum Tab: Hashable { case home, spheres, settings, profile }
    @State private var tab: Tab = .home

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                HomeScreen(
                    store: container.home,
                    userName: container.profile.profile.name,
                    onConfigureProvider: { tab = .settings },
                    onQuickCapture: { await container.quickCapture($0) },
                    onAgentCapture: { await container.agentCapture($0, images: $1) },
                    ritual: container.ritual,
                    insights: container.insights,
                    nudges: container.nudges,
                    reviews: container.reviews,
                    experiments: container.experiments,
                    readiness: container.readiness,
                    agent: container.agent,
                    search: container.search
                )
                .navigationDestination(for: SphereType.self) { sphere in
                    SphereRootScreen(sphere: sphere, container: container)
                }
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(Tab.home)

            NavigationStack {
                SpheresGridScreen(container: container)
            }
            .tabItem { Label("Spheres", systemImage: "circle.hexagongrid.fill") }
            .tag(Tab.spheres)

            NavigationStack {
                SettingsScreen(container: container)
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(Tab.settings)

            NavigationStack {
                ProfileScreen(container: container)
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
            .tag(Tab.profile)
        }
    }
}

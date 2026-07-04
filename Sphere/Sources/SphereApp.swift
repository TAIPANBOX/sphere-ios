import SwiftUI
import SphereCore
import SphereUI

@main
struct SphereApp: App {
    @State private var container = AppContainer()
    @State private var loaded = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if !loaded {
                    ProgressView()
                } else if !container.profile.profile.onboarded {
                    OnboardingFlow(container: container)
                } else {
                    RootView(container: container)
                }
            }
            .task {
                await container.loadAll()
                loaded = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task { await container.runMemoryMaintenance() }
            }
        }
    }
}

struct RootView: View {
    let container: AppContainer

    var body: some View {
        TabView {
            NavigationStack {
                HomeScreen(store: container.home, userName: container.profile.profile.name)
            }
            .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                SpheresGridScreen(container: container)
            }
            .tabItem { Label("Spheres", systemImage: "circle.hexagongrid.fill") }

            NavigationStack {
                SettingsScreen(container: container)
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }

            NavigationStack {
                ProfileScreen(container: container)
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
        }
    }
}

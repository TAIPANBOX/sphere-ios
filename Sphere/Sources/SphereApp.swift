import SwiftUI
import SphereCore
import SphereUI

@main
struct SphereApp: App {
    @State private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("profile.name") private var userName = ""

    var body: some Scene {
        WindowGroup {
            RootView(container: container, userName: $userName)
                .task {
                    await container.loadAll()
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
    @Binding var userName: String

    var body: some View {
        TabView {
            NavigationStack {
                HomeScreen(store: container.home, userName: userName)
            }
            .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                SpheresGridScreen(container: container, userName: userName)
            }
            .tabItem { Label("Spheres", systemImage: "circle.hexagongrid.fill") }

            NavigationStack {
                SettingsScreen(keyStore: container.keyStore)
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }

            NavigationStack {
                ProfileScreen(userName: $userName)
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
        }
    }
}

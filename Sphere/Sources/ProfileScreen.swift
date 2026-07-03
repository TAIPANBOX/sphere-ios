import SwiftUI

/// Minimal Phase-2 Profile: the name every agent addresses the user by.
/// Body metrics, conditions, and dietary tags arrive with the full port.
struct ProfileScreen: View {
    @Binding var userName: String

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $userName)
            } header: {
                Text("Personal")
            } footer: {
                Text("Agents address you by this name and weave it into "
                    + "their memory of your life.")
            }
        }
        .navigationTitle("Profile")
    }
}

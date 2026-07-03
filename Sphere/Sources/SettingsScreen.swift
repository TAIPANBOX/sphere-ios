import SwiftUI
import SphereCore

/// Minimal Phase-2 Settings: AI provider keys (Keychain). Sphere toggles,
/// theme, language, and currency arrive with the full Settings port.
struct SettingsScreen: View {
    let keyStore: KeychainAPIKeyStore

    @State private var keys: [LLMProviderID: String] = [:]
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                ForEach(LLMProviderID.allCases, id: \.self) { provider in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(provider.displayName).font(.subheadline.weight(.medium))
                        SecureField("API key", text: binding(for: provider))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
            } header: {
                Text("AI Agents")
            } footer: {
                Text("Keys are stored in the iCloud Keychain and never leave "
                    + "your devices. The first configured provider (top to "
                    + "bottom) powers your agents.")
            }
        }
        .navigationTitle("Settings")
        .onAppear(perform: loadKeys)
    }

    private func loadKeys() {
        guard !loaded else { return }
        loaded = true
        for provider in LLMProviderID.allCases {
            keys[provider] = keyStore.key(for: provider) ?? ""
        }
    }

    private func binding(for provider: LLMProviderID) -> Binding<String> {
        Binding(
            get: { keys[provider] ?? "" },
            set: { newValue in
                keys[provider] = newValue
                keyStore.set(
                    newValue.trimmingCharacters(in: .whitespaces),
                    for: provider
                )
            }
        )
    }
}

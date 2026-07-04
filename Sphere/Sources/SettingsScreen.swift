import SwiftUI
import SphereCore

/// Phase-2 Settings: AI provider keys (Keychain) and sphere enablement.
/// Theme, language, and currency arrive with the full Settings port.
struct SettingsScreen: View {
    let container: AppContainer

    @State private var keys: [LLMProviderID: String] = [:]
    @State private var loaded = false
    @AppStorage(Prefs.theme) private var theme = ThemePreference.system.rawValue
    @AppStorage(Prefs.currency) private var currency = Currency.deviceDefault.rawValue

    private static let emojis: [SphereType: String] = [
        .health: "🫀", .learning: "📚", .career: "💼", .finance: "💰",
        .relationships: "💜", .rest: "🌊", .hobbies: "🎸", .travel: "✈️",
        .mindfulness: "🧘", .creativity: "🎨", .home: "🏡", .goals: "🎯",
    ]

    var body: some View {
        Form {
            Section {
                ForEach(LLMProviderID.allCases, id: \.self) { provider in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(provider.displayName).font(.subheadline.weight(.medium))
                        SecureField("API key", text: keyBinding(for: provider))
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

            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(ThemePreference.allCases, id: \.rawValue) { pref in
                        Text(pref.label).tag(pref.rawValue)
                    }
                }
                Picker("Currency", selection: $currency) {
                    ForEach(Currency.allCases, id: \.rawValue) { currency in
                        Text(currency.label).tag(currency.rawValue)
                    }
                }
            }

            Section("My Spheres") {
                ForEach(SphereType.allCases, id: \.self) { sphere in
                    Toggle(isOn: sphereBinding(for: sphere)) {
                        Text("\(Self.emojis[sphere] ?? "✨") \(sphere.rawValue.capitalized)")
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear(perform: loadKeys)
    }

    private func loadKeys() {
        guard !loaded else { return }
        loaded = true
        for provider in LLMProviderID.allCases {
            keys[provider] = container.keyStore.key(for: provider) ?? ""
        }
    }

    private func keyBinding(for provider: LLMProviderID) -> Binding<String> {
        Binding(
            get: { keys[provider] ?? "" },
            set: { newValue in
                keys[provider] = newValue
                container.keyStore.set(newValue.trimmingCharacters(in: .whitespaces), for: provider)
            }
        )
    }

    private func sphereBinding(for sphere: SphereType) -> Binding<Bool> {
        Binding(
            get: { container.profile.profile.isSphereActive(sphere) },
            set: { active in
                Task { try? await container.profile.setSphereActive(sphere, active: active) }
            }
        )
    }
}

import SwiftUI
import SphereCore
import SphereUI
import UIKit

/// Settings: AI provider keys (Keychain), notifications, privacy & data
/// (Face ID lock, export), appearance, and sphere enablement.
struct SettingsScreen: View {
    let container: AppContainer

    @State private var keys: [LLMProviderID: String] = [:]
    @State private var loaded = false
    @State private var exportItem: ExportItem?
    @State private var exporting = false
    @AppStorage(Prefs.theme) private var theme = ThemePreference.system.rawValue
    @AppStorage(Prefs.currency) private var currency = Currency.deviceDefault.rawValue
    @AppStorage(Prefs.appLock) private var appLock = false
    @AppStorage(Prefs.aiBackend) private var aiBackend = ""
    @AppStorage(Prefs.cloudModel) private var cloudModel = ""
    @AppStorage(Prefs.language) private var language = AppLanguage.system.rawValue
    @State private var cloudModelName: String?
    private let onDeviceAvailable = OnDeviceAI.isAvailable

    private var cloudModelLabel: String {
        guard !cloudModel.isEmpty else { return String(localized: "Default") }
        return cloudModelName ?? cloudModel
    }

    /// Live check against the field's current text, so the picker row appears
    /// the moment a real-looking key is pasted and disappears when it's cleared.
    private var hasPlausibleOpenRouterKey: Bool {
        LLMProviderID.openrouter.isPlausibleKey(keys[.openrouter] ?? "")
    }

    var body: some View {
        Form {
            Section {
                Picker("Assistant", selection: $aiBackend) {
                    Text("Automatic").tag("")
                    if onDeviceAvailable {
                        Text(AIBackend.onDevice.localizedTitle).tag("onDevice")
                    }
                    if !container.models.installedModels.isEmpty {
                        Text(AIBackend.localModel.localizedTitle).tag("localModel")
                    }
                    ForEach(LLMProviderID.allCases, id: \.self) { provider in
                        Text(provider.localizedTitle).tag(provider.rawValue)
                    }
                }
                NavigationLink("Downloadable models") {
                    ModelsScreen(manager: container.models)
                }
            } header: {
                Text("AI")
            } footer: {
                if onDeviceAvailable {
                    Text("On-device AI is free and private — nothing leaves your iPhone, no key needed. Add a key below only if you want a cloud model.")
                } else {
                    Text("Add a provider key below, or use this iPhone's free on-device AI where available (iPhone 15 Pro or newer on iOS 26).")
                }
            }

            Section {
                ForEach(LLMProviderID.allCases, id: \.self) { provider in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(provider.localizedTitle).font(.subheadline.weight(.medium))
                        SecureField("API key", text: keyBinding(for: provider))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                // The model picker only makes sense with a working key, so it
                // stays hidden until the entered text at least looks like an
                // OpenRouter key — random input must not reveal it.
                if hasPlausibleOpenRouterKey {
                    NavigationLink {
                        CloudModelsScreen(
                            catalog: container.cloudModels,
                            selectedID: { CloudModelPreference.current },
                            setSelectedID: { CloudModelPreference.current = $0 }
                        )
                    } label: {
                        HStack {
                            Text("Cloud model")
                            Spacer()
                            Text(cloudModelLabel).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("API keys (optional)")
            } footer: {
                Text("Keys are stored in the iCloud Keychain and never leave your devices. Used only when you select a cloud model above.")
            }

            Section {
                Toggle(isOn: notificationBinding(.morningBrief)) { Text(NotificationCategory.morningBrief.localizedTitle) }
                Toggle(isOn: notificationBinding(.water)) { Text(NotificationCategory.water.localizedTitle) }
                Toggle(isOn: notificationBinding(.medication)) { Text(NotificationCategory.medication.localizedTitle) }
                Toggle(isOn: notificationBinding(.bedtime)) { Text(NotificationCategory.bedtime.localizedTitle) }
                Toggle(isOn: notificationBinding(.plant)) { Text(NotificationCategory.plant.localizedTitle) }
                Toggle(isOn: notificationBinding(.subscription)) { Text(NotificationCategory.subscription.localizedTitle) }
                Toggle(isOn: notificationBinding(.habit)) { Text(NotificationCategory.habit.localizedTitle) }
                Toggle(isOn: notificationBinding(.birthday)) { Text(NotificationCategory.birthday.localizedTitle) }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Reminders are built from your own data and stay on this device. Bedtime needs a bedtime set in Rest; medication and plant reminders appear once you add them.")
            }

            Section {
                Toggle("Face ID lock", isOn: $appLock)
                Button {
                    Task { await runExport() }
                } label: {
                    HStack {
                        Text("Export all data")
                        Spacer()
                        if exporting { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(exporting)
                NavigationLink("Privacy & data") { PrivacyScreen() }
            } header: {
                Text("Privacy & Data")
            } footer: {
                Text("Everything stays on this device. Export saves a JSON copy of all your data; Face ID keeps it private.")
            }

            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(ThemePreference.allCases, id: \.rawValue) { pref in
                        Text(LocalizedStringKey(pref.label)).tag(pref.rawValue)
                    }
                }
                Picker("Currency", selection: $currency) {
                    ForEach(Currency.allCases, id: \.rawValue) { currency in
                        Text(currency.label).tag(currency.rawValue)
                    }
                }
            }

            Section {
                NavigationLink("My Spheres") { MySpheresScreen(container: container) }
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { option in
                        Text(option.nativeName).tag(option.rawValue)
                    }
                }
            } header: {
                Text("General")
            } footer: {
                Text("Takes full effect after reopening the app.")
            }

            Section {
                NavigationLink("About") { AboutScreen() }
            }
        }
        .navigationTitle("Settings")
        .onAppear(perform: loadKeys)
        .onChange(of: appLock) { _, enabled in
            Task { try? await container.profile.update { $0.appLockEnabled = enabled } }
        }
        .task(id: cloudModel) { await loadCloudModelName() }
        .sheet(item: $exportItem) { item in
            ShareSheet(url: item.url)
        }
    }

    /// Resolves the friendly name for the selected cloud model id from the
    /// catalog (cache-first, so this is normally instant); falls back to
    /// showing the raw id when the catalog hasn't loaded yet.
    private func loadCloudModelName() async {
        guard !cloudModel.isEmpty else { cloudModelName = nil; return }
        let models = await container.cloudModels.load()
        cloudModelName = models.first { $0.id == cloudModel }?.name
    }

    /// Two-way toggle for a per-category notification preference; persists to
    /// the profile and re-syncs reminders so the change takes effect at once.
    private func notificationBinding(_ category: NotificationCategory) -> Binding<Bool> {
        Binding(
            get: {
                container.profile.profile.notificationEnabled(
                    category.rawValue, default: category.defaultOn
                )
            },
            set: { enabled in
                Task {
                    try? await container.profile.update {
                        $0.notificationPrefs[category.rawValue] = enabled
                    }
                    await container.refreshReminders()
                }
            }
        )
    }

    private func runExport() async {
        exporting = true
        defer { exporting = false }
        guard let data = try? await DataExporter.exportJSON(from: container.database) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sphere-export.json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        exportItem = ExportItem(url: url)
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
}

/// Identifiable wrapper so the exported file URL can drive a `.sheet(item:)`.
private struct ExportItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// Minimal UIActivityViewController bridge for sharing/saving the export file.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

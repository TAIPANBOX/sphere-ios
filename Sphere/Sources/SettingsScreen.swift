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
    private let onDeviceAvailable = OnDeviceAI.isAvailable

    var body: some View {
        Form {
            Section {
                Picker("Assistant", selection: $aiBackend) {
                    Text("Automatic").tag("")
                    if onDeviceAvailable {
                        Text("On-device (free)").tag("onDevice")
                    }
                    ForEach(LLMProviderID.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                NavigationLink("Downloadable models") {
                    ModelsScreen(manager: container.models)
                }
            } header: {
                Text("AI")
            } footer: {
                Text(onDeviceAvailable
                    ? "On-device AI is free and private — nothing leaves your "
                        + "iPhone, no key needed. Add a key below only if you want "
                        + "a cloud model."
                    : "Add a provider key below, or use this iPhone's free "
                        + "on-device AI where available (iPhone 15 Pro or newer on "
                        + "iOS 26).")
            }

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
                Text("API keys (optional)")
            } footer: {
                Text("Keys are stored in the iCloud Keychain and never leave "
                    + "your devices. Used only when you select a cloud model above.")
            }

            Section("Notifications") {
                Toggle("Birthday reminders", isOn: notificationBinding(.birthday))
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
                Text("Everything stays on this device. Export saves a JSON copy "
                    + "of all your data; Face ID keeps it private.")
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

            Section("General") {
                NavigationLink("My Spheres") { MySpheresScreen(container: container) }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Text("Language").foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
        .sheet(item: $exportItem) { item in
            ShareSheet(url: item.url)
        }
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
                    if category == .birthday { await container.refreshBirthdayReminders() }
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

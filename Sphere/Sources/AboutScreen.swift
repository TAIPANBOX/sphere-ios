import SwiftUI

/// App version, one-line ethos, and open-source acknowledgements.
struct AboutScreen: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Text("🌐").font(.system(size: 56))
                    Text("Sphere").font(.title2.weight(.bold))
                    Text("An AI companion for all 12 spheres of your life — private and on-device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Version \(version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Privacy") {
                NavigationLink("Privacy & data") { PrivacyScreen() }
            }

            Section("Legal") {
                NavigationLink("Terms of Service") { TermsScreen() }
                NavigationLink("Privacy Policy") { PrivacyPolicyScreen() }
            }

            Section("Acknowledgements") {
                acknowledgement("GRDB.swift", "MIT — SQLite persistence")
                acknowledgement("Open-Meteo", "Free weather API, no key")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func acknowledgement(_ name: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.subheadline.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

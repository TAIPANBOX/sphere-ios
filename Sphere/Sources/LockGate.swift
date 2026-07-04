import SwiftUI
import LocalAuthentication

/// Wraps the app content behind Face ID / Touch ID when `Prefs.appLock` is on.
/// Locks whenever the scene leaves the foreground and re-authenticates on
/// return, so health / finance / journal data isn't visible from the app
/// switcher or to someone who picks up an unlocked phone.
struct LockGate<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @AppStorage(Prefs.appLock) private var lockEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var unlocked = false
    @State private var authing = false

    var body: some View {
        ZStack {
            content()
                .opacity(shouldObscure ? 0 : 1)

            if shouldObscure {
                LockedView(retry: authenticate)
            }
        }
        .task(id: lockEnabled) {
            if lockEnabled, !unlocked { await authenticate() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if lockEnabled, !unlocked { Task { await authenticate() } }
            case .background:
                unlocked = false // require re-auth on return
            default:
                break
            }
        }
    }

    private var shouldObscure: Bool { lockEnabled && !unlocked }

    @MainActor
    private func authenticate() async {
        guard lockEnabled, !unlocked, !authing else { return }
        authing = true
        defer { authing = false }

        let context = LAContext()
        context.localizedFallbackTitle = "Use passcode"
        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        do {
            unlocked = try await context.evaluatePolicy(policy, localizedReason: "Unlock Sphere")
        } catch {
            unlocked = false
        }
    }
}

private struct LockedView: View {
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Sphere is locked").font(.headline)
            Button("Unlock") { Task { await retry() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

/// Static explanation of the app's local-first privacy stance (N7).
struct PrivacyScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Your data stays on your device", systemImage: "hand.raised.fill")
                    .font(.title3.weight(.semibold))
                privacyPoint(
                    "Local-first",
                    "Every sphere, journal entry, health log and memory lives in a "
                        + "database on this device. Sphere has no account and no server "
                        + "of its own."
                )
                privacyPoint(
                    "Your AI, your choice",
                    "The on-device model runs entirely on your phone — nothing leaves "
                        + "it. If you choose to connect a Claude or ChatGPT key instead, "
                        + "only the messages for that chat are sent to that provider, "
                        + "using your own key."
                )
                privacyPoint(
                    "You hold the exit",
                    "Export all your data to a JSON file at any time from Settings. "
                        + "Nothing locks you in."
                )
                privacyPoint(
                    "Locked if you want",
                    "Turn on Face ID lock so your life data can't be read from the app "
                        + "switcher or by anyone who picks up your phone."
                )
            }
            .padding()
        }
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacyPoint(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

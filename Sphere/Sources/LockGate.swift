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
                .opacity(contentVisible ? 1 : 0)
                .disabled(!contentVisible)
                .accessibilityHidden(!contentVisible)

            if needsAuth {
                LockedView(retry: authenticate)
            } else if privacyCover {
                PrivacyCoverView()
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

    /// Face ID hasn't succeeded this session — show the unlock prompt.
    private var needsAuth: Bool { lockEnabled && !unlocked }

    /// Unlocked, but the scene isn't active (app switcher, Control Center, an
    /// incoming call): hide the content from the snapshot without forcing a
    /// re-auth for a momentary interruption. A real background still clears
    /// `unlocked`, so returning from it re-authenticates.
    private var privacyCover: Bool { lockEnabled && unlocked && scenePhase != .active }

    private var contentVisible: Bool { !needsAuth && !privacyCover }

    @MainActor
    private func authenticate() async {
        guard lockEnabled, !unlocked, !authing else { return }
        authing = true
        defer { authing = false }

        let context = LAContext()
        context.localizedFallbackTitle = "Use passcode"
        var error: NSError?
        let canBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let canDeviceAuth = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)

        // No biometrics AND no device passcode — there's nothing to
        // authenticate against. Fail open so the lock can never trap the user
        // out of their own data (a device with no passcode has no boundary).
        guard canBiometrics || canDeviceAuth else {
            unlocked = true
            return
        }

        let policy: LAPolicy = canBiometrics
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

/// An opaque cover shown while unlocked but not foreground-active, so the
/// app-switcher snapshot never captures the user's data. No button: it clears
/// itself the moment the scene becomes active again.
private struct PrivacyCoverView: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 44))
            .foregroundStyle(.secondary)
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
                        + "it. If you choose to connect OpenRouter with your own key "
                        + "instead, only the messages for that chat are sent to that "
                        + "provider, using your own key."
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

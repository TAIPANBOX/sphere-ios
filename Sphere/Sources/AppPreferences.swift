import SwiftUI
import SphereCore

/// App-wide display preferences (theme, currency). These are device-level UI
/// choices, not agent context, so they live in UserDefaults via @AppStorage
/// rather than the profile/database.
enum Prefs {
    static let theme = "pref.theme"
    static let currency = "pref.currency"
    static let appLock = "pref.appLock"
    /// Selected AI backend: "" = auto, "onDevice", or a provider rawValue.
    static let aiBackend = "pref.aiBackend"
    /// Active downloaded on-device model id (nil = none selected).
    static let activeModel = "pref.activeModel"
}

/// Reads the user's explicit AI-backend choice from UserDefaults (nil = auto,
/// which prefers free on-device, then the first configured cloud key).
enum AppBackendPreference {
    static var current: AIBackend? {
        guard let raw = UserDefaults.standard.string(forKey: Prefs.aiBackend),
              !raw.isEmpty else { return nil }
        return AIBackend(storageValue: raw)
    }
}

enum ThemePreference: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension View {
    /// Reads the stored currency (falling back to the device default) as a
    /// typed `Currency`.
    func storedCurrency(_ raw: String) -> Currency {
        Currency(rawValue: raw) ?? .deviceDefault
    }
}

/// Emoji for each sphere, shared across Settings, the grid, and the My Spheres
/// editor.
func sphereEmoji(_ sphere: SphereType) -> String {
    switch sphere {
    case .health: "🫀"
    case .learning: "📚"
    case .career: "💼"
    case .finance: "💰"
    case .relationships: "💜"
    case .rest: "🌊"
    case .hobbies: "🎸"
    case .travel: "✈️"
    case .mindfulness: "🧘"
    case .creativity: "🎨"
    case .home: "🏡"
    case .goals: "🎯"
    }
}

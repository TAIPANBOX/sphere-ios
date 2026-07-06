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
    /// Chosen OpenRouter model id (empty/nil = provider default).
    static let cloudModel = "pref.cloudModel"
    /// In-app language override: "" = System, or a supported language code
    /// ("en", "uk"). See `LanguagePreference`.
    static let language = "pref.language"
}

/// Reads/writes the user's chosen OpenRouter model id (nil = provider default).
enum CloudModelPreference {
    static var current: String? {
        get {
            let value = UserDefaults.standard.string(forKey: Prefs.cloudModel)
            return (value?.isEmpty ?? true) ? nil : value
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Prefs.cloudModel)
        }
    }
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

/// Applies (or clears) the `AppleLanguages` override so the next cold launch
/// starts fully in the chosen language, including formatters and
/// `String(localized:)` snapshot sites (see `AppLanguage` for why this is
/// needed in addition to the immediate `.environment(\.locale, ...)` override
/// applied in `SphereApp`). Safe to call every time the preference changes;
/// `.system` removes any override.
extension AppLanguage {
    func applyAppleLanguagesOverride() {
        switch self {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        default:
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
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

    /// Applies the chosen in-app language as a SwiftUI environment override.
    /// `.system` leaves the environment untouched so the app follows the
    /// device locale exactly as before this feature existed.
    @ViewBuilder
    func appLanguage(_ language: AppLanguage) -> some View {
        if let locale = language.locale {
            self.environment(\.locale, locale)
        } else {
            self
        }
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

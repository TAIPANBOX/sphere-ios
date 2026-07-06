import Foundation

/// In-app language override, shared by the app target, the widget extension,
/// and (for reference) the watch, which stays on the watchOS system
/// language and never reads this.
///
/// `.system` follows the device language (no override, `locale` is `nil`);
/// otherwise it pins the UI to one supported language. See
/// `Sphere/Sources/AppPreferences.swift` for the SwiftUI-facing
/// `.appLanguage(_:)` view modifier that applies `locale` to the
/// environment, and for why an `AppleLanguages` `UserDefaults` override is
/// also needed for full (formatter-level) coverage on the next cold launch.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system = ""
    case english = "en"
    case ukrainian = "uk"

    /// Shown in its own language, not the current display language, so users
    /// can find their language even if the UI is currently in another one.
    public var nativeName: String {
        switch self {
        case .system: "System"
        case .english: "English"
        case .ukrainian: "Українська"
        }
    }

    /// `nil` for `.system` — callers should leave the SwiftUI environment
    /// untouched in that case, so the app follows the device locale.
    public var locale: Locale? {
        switch self {
        case .system: nil
        default: Locale(identifier: rawValue)
        }
    }
}

/// Reads/writes the chosen language into the shared App Group so the widget
/// extension — a separate process with its own `Locale.current`/
/// `Bundle.main`, unaffected by the app's `AppleLanguages` override — can
/// apply the same `.environment(\.locale, ...)` override to its own views.
public enum SharedAppLanguage {
    private static let key = "pref.language"

    public static func write(_ language: AppLanguage, groupID: String = WidgetSnapshotStore.appGroupID) {
        UserDefaults(suiteName: groupID)?.set(language.rawValue, forKey: key)
    }

    /// `.system` (no override) if there is no stored preference or the App
    /// Group is unavailable.
    public static func current(groupID: String = WidgetSnapshotStore.appGroupID) -> AppLanguage {
        let raw = UserDefaults(suiteName: groupID)?.string(forKey: key) ?? ""
        return AppLanguage(rawValue: raw) ?? .system
    }
}

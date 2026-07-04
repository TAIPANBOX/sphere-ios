import SwiftUI
import SphereCore

/// App-wide display preferences (theme, currency). These are device-level UI
/// choices, not agent context, so they live in UserDefaults via @AppStorage
/// rather than the profile/database.
enum Prefs {
    static let theme = "pref.theme"
    static let currency = "pref.currency"
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

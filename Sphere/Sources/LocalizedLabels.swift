import SwiftUI
import SphereCore

// SphereCore enums expose a `.label`/`.displayName` `String` for data/logging
// purposes; those are plain English literals (SphereCore has no localization
// of its own — it isn't UI). Rendering them directly as `Text($0.label)`
// calls the *verbatim* `Text(_: some StringProtocol)` initializer, which
// never looks anything up in a String Catalog, in any locale. The fix is a
// UI-layer switch, here, that maps each case to a `Text` backed by the
// app-shell catalog (`Sphere/Sources/Localizable.xcstrings`) instead of
// rendering the SphereCore string directly.

extension NotificationCategory {
    /// Localized title for the Settings notification toggles. Mirrors
    /// `label`'s English wording so the catalog keys read naturally.
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .birthday: "Birthdays"
        case .water: "Water reminders"
        case .medication: "Medication times"
        case .bedtime: "Bedtime wind-down"
        case .plant: "Plant watering"
        case .subscription: "Subscription renewals"
        case .morningBrief: "Morning brief"
        case .nudge: "Proactive nudges"
        case .habit: "Habit reminders"
        }
    }
}

extension AIBackend {
    /// Localized title for the Assistant picker. `.cloud` defers to the
    /// provider's own localized name.
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .onDevice: "On-device (free)"
        case .localModel: "Downloaded model"
        case .cloud(let provider): provider.localizedTitle
        }
    }
}

extension LLMProviderID {
    /// OpenRouter is a proper noun and identical in every supported
    /// language, but still routed through the catalog for consistency and
    /// in case a future provider's name needs translation.
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .openrouter: "OpenRouter"
        }
    }
}

extension Gender {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .other: "Other"
        case .preferNotToSay: "Prefer not to say"
        }
    }
}

extension BloodType {
    /// Blood-type notation ("A+", "O−", …) is locale-invariant, but still
    /// routed through `Text(_:)`'s verbatim initializer via `label` — no
    /// catalog entry needed since there is nothing to translate.
    var localizedTitle: String { label }
}

extension WellbeingMode {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .normal: "Normal"
        case .sick: "Sick"
        case .vacation: "Vacation"
        }
    }
}

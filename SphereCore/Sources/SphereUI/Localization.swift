import SwiftUI

// SwiftUI resolves a plain `Text("literal")` (and the string-literal convenience
// inits on `Button`, `Label`, `TextField`, `Section`, `.navigationTitle`) against
// `Bundle.main` by default. Package code lives in `Bundle.module`, so those
// plain forms silently miss the SphereUI string catalog and always render the
// English source string, regardless of the user's locale. Verified experimentally
// (see commit body): the app-shell catalog resolves correctly under a forced
// Ukrainian locale, but SphereUI's own strings did not, until routed through
// `Bundle.module` explicitly.
//
// `Text(ui:)` is the terse fix for plain text. Call sites that need a string
// title on `Button`/`Label`/`TextField`/`Section`/`.navigationTitle` use the
// label-closure form with `Text(ui:)` instead of the string-literal convenience
// initializer, since those initializers have no `bundle:` parameter.
extension Text {
    init(ui key: LocalizedStringKey) {
        self.init(key, bundle: .module)
    }
}

/// For call sites that need a resolved `String` (not a `Text` view) — e.g.
/// passing a title into a component whose parameter is typed `String`, where
/// `LocalizedStringKey` inference never kicks in and a plain literal would
/// render verbatim in every locale.
func uiString(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}

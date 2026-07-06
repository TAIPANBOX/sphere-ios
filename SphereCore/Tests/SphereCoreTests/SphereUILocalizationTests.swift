import Foundation
import Testing
@testable import SphereUI

/// Guards the resource wiring for SphereUI's Ukrainian localization (C9).
/// This is the fragile part: SwiftUI resolves plain `Text("literal")` against
/// `Bundle.main`, not a package's `Bundle.module`, so a missing `bundle:
/// .module` anywhere in the pipeline (Package.swift resources declaration,
/// the Text(ui:)/uiString(_:) helpers, or the catalog itself) silently falls
/// back to English with no compile-time signal.
///
/// `swift test` builds via the SwiftPM CLI, which — unlike Xcode's build
/// system — copies `Localizable.xcstrings` into `Bundle.module` uncompiled
/// (no per-locale `.lproj`/`.strings` are generated), so `Bundle.module
/// .localizations` and `String(localized:bundle:locale:)` both report only
/// "en" here even though the real app build (verified manually via the iOS
/// Simulator with a forced Ukrainian locale) resolves `uk` correctly. These
/// tests therefore verify the catalog's content and resource wiring directly
/// — that the file ships in the package bundle, is valid JSON in the
/// String Catalog schema, and carries "uk" translations for known keys —
/// rather than routing through Foundation's locale-resolution APIs.
@Suite("SphereUI Ukrainian localization")
struct SphereUILocalizationTests {
    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localizations: Decodable {
                struct UK: Decodable {
                    struct StringUnit: Decodable {
                        let state: String
                        let value: String
                    }
                    let stringUnit: StringUnit
                }
                let uk: UK?
            }
            let localizations: Localizations?
        }
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private func loadCatalog() throws -> Catalog {
        let url = try #require(
            Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
            "Localizable.xcstrings must ship as a resource in the SphereUI bundle"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    @Test func catalogShipsInSphereUIBundleWithEnglishSource() throws {
        let catalog = try loadCatalog()
        #expect(catalog.sourceLanguage == "en")
        #expect(!catalog.strings.isEmpty)
    }

    @Test func knownKeysHaveTranslatedUkrainianEntries() throws {
        let catalog = try loadCatalog()
        let cases: [(key: String, expected: String)] = [
            ("Overall Life Progress", "Загальний прогрес життя"),
            ("Cancel", "Скасувати"),
            ("Save", "Зберегти"),
            ("Delete", "Видалити"),
        ]
        for (key, expected) in cases {
            let entry = try #require(catalog.strings[key], "missing catalog entry for '\(key)'")
            let uk = try #require(entry.localizations?.uk, "missing uk localization for '\(key)'")
            #expect(uk.stringUnit.state == "translated")
            #expect(uk.stringUnit.value == expected)
        }
    }

    @Test func moduleBundleIsDeclaredAsAResourceBundle() {
        // Guards the Package.swift wiring: SphereUI must declare
        // `defaultLocalization` and process the catalog as a resource, or
        // Bundle.module itself would fail to resolve/load at all.
        #expect(Bundle.module.bundlePath.contains("SphereUI"))
    }
}

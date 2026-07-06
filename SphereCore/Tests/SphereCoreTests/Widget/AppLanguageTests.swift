import Foundation
import Testing
@testable import SphereCore

@Suite("AppLanguage")
struct AppLanguageTests {
    @Test func systemHasNoLocaleOverride() {
        #expect(AppLanguage.system.locale == nil)
    }

    @Test func nonSystemCasesMapToTheMatchingLocale() {
        #expect(AppLanguage.english.locale?.identifier == "en")
        #expect(AppLanguage.ukrainian.locale?.identifier == "uk")
    }

    @Test func nativeNamesAreShownInTheirOwnLanguage() {
        #expect(AppLanguage.system.nativeName == "System")
        #expect(AppLanguage.english.nativeName == "English")
        #expect(AppLanguage.ukrainian.nativeName == "Українська")
    }

    @Test func sharedAppLanguageRoundTripsThroughTheAppGroupSuite() {
        let suite = "test-suite-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        // No stored value yet — defaults to System.
        #expect(SharedAppLanguage.current(groupID: suite) == .system)

        SharedAppLanguage.write(.ukrainian, groupID: suite)
        #expect(SharedAppLanguage.current(groupID: suite) == .ukrainian)

        SharedAppLanguage.write(.system, groupID: suite)
        #expect(SharedAppLanguage.current(groupID: suite) == .system)
    }
}

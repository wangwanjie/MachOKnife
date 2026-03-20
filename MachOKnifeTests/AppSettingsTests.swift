import Foundation
import Testing
@testable import MachOKnife

struct AppSettingsTests {
    @Test("language resolution falls back to the closest supported localization")
    func languageResolutionFallsBackToClosestSupportedLocalization() throws {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        #expect(settings.language == .system)
        #expect(settings.resolvedLanguage(preferredLanguages: ["zh-Hant-TW"]) == .traditionalChinese)
        #expect(settings.resolvedLanguage(preferredLanguages: ["zh-Hans-CN"]) == .simplifiedChinese)
        #expect(settings.resolvedLanguage(preferredLanguages: ["fr-FR"]) == .english)
    }

    @Test("recent file limit defaults to 50")
    func recentFileLimitDefaultsToFifty() throws {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        #expect(settings.recentFilesLimit == 50)
    }

    @Test("theme selection persists across settings instances")
    func themeSelectionPersistsAcrossSettingsInstances() throws {
        let defaults = makeDefaults()

        let initialSettings = AppSettings(defaults: defaults)
        initialSettings.theme = .dark

        let reloadedSettings = AppSettings(defaults: defaults)
        #expect(reloadedSettings.theme == .dark)
    }

    private func makeDefaults(fileID: String = #fileID, line: Int = #line) -> UserDefaults {
        let suiteName = "MachOKnifeTests.\(fileID).\(line).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

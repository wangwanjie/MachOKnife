import AppKit
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

    @Test("CLI install directory persists across settings instances")
    func cliInstallDirectoryPersistsAcrossSettingsInstances() throws {
        let defaults = makeDefaults()
        let installDirectory = FileManager.default.canonicalTemporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)

        let initialSettings = AppSettings(defaults: defaults)
        try initialSettings.setCLIInstallDirectory(installDirectory)

        let reloadedSettings = AppSettings(defaults: defaults)
        #expect(try reloadedSettings.cliInstallDirectoryURL() == installDirectory)
    }

    @Test("explicit script subtags win over region when resolving Chinese")
    func chineseResolutionPrefersScriptOverRegion() {
        // 回归：此前按子串匹配地区，"zh-Hans-HK"（香港地区的简体中文）会被误判为繁体。
        #expect(AppLanguage.resolve(preferredLanguages: ["zh-Hans-HK"]) == .simplifiedChinese)
        #expect(AppLanguage.resolve(preferredLanguages: ["zh-Hans-TW"]) == .simplifiedChinese)
        #expect(AppLanguage.resolve(preferredLanguages: ["zh-Hant-CN"]) == .traditionalChinese)
        #expect(AppLanguage.resolve(preferredLanguages: ["zh-HK"]) == .traditionalChinese)
        #expect(AppLanguage.resolve(preferredLanguages: ["zh-MO"]) == .traditionalChinese)
        #expect(AppLanguage.resolve(preferredLanguages: ["zh_TW"]) == .traditionalChinese)
        #expect(AppLanguage.resolve(preferredLanguages: ["zh-CN"]) == .simplifiedChinese)
        #expect(AppLanguage.resolve(preferredLanguages: ["zh"]) == .simplifiedChinese)
    }

    @Test("language resolution skips unsupported languages and defaults to English")
    func languageResolutionSkipsUnsupportedLanguages() {
        #expect(AppLanguage.resolve(preferredLanguages: ["fr-FR", "zh-Hant-TW", "en-US"]) == .traditionalChinese)
        #expect(AppLanguage.resolve(preferredLanguages: ["de", "en-GB"]) == .english)
        #expect(AppLanguage.resolve(preferredLanguages: []) == .english)
    }

    @Test("an explicit language overrides the system preference")
    func explicitLanguageOverridesSystemPreference() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.language = .traditionalChinese

        #expect(settings.resolvedLanguage(preferredLanguages: ["en-US"]) == .traditionalChinese)
        #expect(AppSettings(defaults: makeDefaults()).resolvedLanguage(preferredLanguages: ["en-US"]) == .english)
    }

    @Test("recent file limit is clamped to at least one")
    func recentFileLimitIsClampedToAtLeastOne() {
        let settings = AppSettings(defaults: makeDefaults())

        settings.recentFilesLimit = 0
        #expect(settings.recentFilesLimit == 1)

        settings.recentFilesLimit = -5
        #expect(settings.recentFilesLimit == 1)

        settings.recentFilesLimit = 12
        #expect(settings.recentFilesLimit == 12)
    }

    @Test("clearing the CLI install directory and executable path removes the stored values")
    func clearingCLISettingsRemovesStoredValues() throws {
        let settings = AppSettings(defaults: makeDefaults())
        let installDirectory = FileManager.default.canonicalTemporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)

        try settings.setCLIInstallDirectory(installDirectory)
        settings.setLastKnownCLIExecutablePath(installDirectory.appendingPathComponent("machoe-cli").path)
        #expect(try settings.cliInstallDirectoryURL() != nil)
        #expect(settings.lastKnownCLIExecutablePath() != nil)

        settings.clearCLIInstallDirectory()
        settings.clearLastKnownCLIExecutablePath()

        #expect(try settings.cliInstallDirectoryURL() == nil)
        #expect(settings.lastKnownCLIExecutablePath() == nil)

        // 空字符串视为“没有记录”。
        settings.setLastKnownCLIExecutablePath("")
        #expect(settings.lastKnownCLIExecutablePath() == nil)
    }

    @Test("theme maps to the expected NSAppearance")
    func themeMapsToAppearance() {
        let settings = AppSettings(defaults: makeDefaults())

        settings.theme = .system
        #expect(settings.effectiveAppearance() == nil)

        settings.theme = .light
        #expect(settings.effectiveAppearance()?.name == .aqua)

        settings.theme = .dark
        #expect(settings.effectiveAppearance()?.name == .darkAqua)
    }

    private func makeDefaults(fileID: String = #fileID, line: Int = #line) -> UserDefaults {
        let suiteName = "MachOKnifeTests.\(fileID).\(line).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

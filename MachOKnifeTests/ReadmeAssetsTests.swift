import AppKit
import Foundation
import Testing
@testable import MachOKnife

@MainActor
struct ReadmeAssetsTests {
    @Test("render README screenshots")
    func renderReadmeScreenshots() throws {
        let suiteName = "MachOKnifeTests.ReadmeAssets.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        settings.language = .english
        settings.theme = .light

        let originalAppearance = NSApp.appearance
        NSApp.appearance = settings.effectiveAppearance()

        let originalSettingsProvider = L10n.settingsProvider
        let originalBundleProvider = L10n.bundleProvider
        L10n.settingsProvider = { settings }
        L10n.bundleProvider = { .main }

        defer {
            NSApp.appearance = originalAppearance
            L10n.settingsProvider = originalSettingsProvider
            L10n.bundleProvider = originalBundleProvider
            defaults.removePersistentDomain(forName: suiteName)
        }

        let updateManager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(feedURLString: "", publicEDKey: "")
            },
            clientProvider: { nil }
        )

        let mainWindowController = MainWindowController()
        let preferencesWindowController = PreferencesWindowController(
            settings: settings,
            updateManager: updateManager
        )

        _ = mainWindowController.window
        _ = preferencesWindowController.window

        let fixtureURL = repoRoot()
            .appendingPathComponent("Resources")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("cli")
            .appendingPathComponent("libCLIEditable.dylib")

        #expect(mainWindowController.openDocument(at: fixtureURL))

        mainWindowController.window?.setFrame(NSRect(x: 0, y: 0, width: 1680, height: 1040), display: true)
        preferencesWindowController.window?.setFrame(NSRect(x: 0, y: 0, width: 980, height: 760), display: true)

        mainWindowController.present(nil)
        preferencesWindowController.present(nil)
        preferencesWindowController.selectTab(at: 3)
        pumpRunLoop(for: 1.0)

        let screenshotsDirectory = screenshotOutputDirectory()
        print("README screenshot output: \(screenshotsDirectory.path)")
        try WindowSnapshot.writePNG(
            for: mainWindowController.window,
            to: screenshotsDirectory.appendingPathComponent("main-window.png")
        )
        try WindowSnapshot.writePNG(
            for: preferencesWindowController.window,
            to: screenshotsDirectory.appendingPathComponent("preferences-updates.png")
        )

        #expect(FileManager.default.fileExists(atPath: screenshotsDirectory.appendingPathComponent("main-window.png").path))
        #expect(FileManager.default.fileExists(atPath: screenshotsDirectory.appendingPathComponent("preferences-updates.png").path))

        mainWindowController.window?.close()
        preferencesWindowController.window?.close()
    }

    private func repoRoot() -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func pumpRunLoop(for duration: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }

    private func screenshotOutputDirectory() -> URL {
        if let environmentPath = ProcessInfo.processInfo.environment["MACHOKNIFE_SCREENSHOT_DIR"], !environmentPath.isEmpty {
            return URL(filePath: environmentPath, directoryHint: .isDirectory)
        }

        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MachOKnife", isDirectory: true)
            .appendingPathComponent("ReadmeScreenshots", isDirectory: true)
    }
}

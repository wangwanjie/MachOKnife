import AppKit
import CoreMachO
import Foundation
import MachOKnifeKit
import Testing
@testable import MachOKnife

@MainActor
struct LocalizationRefreshTests {
    @Test("close file requires confirmation before clearing the active workspace")
    func closeFileRequiresConfirmationBeforeClearingWorkspace() throws {
        let controller = MainWindowController()
        let fixtureURL = try makeEditableFixtureCopy()

        #expect(controller.openDocument(at: fixtureURL))
        #expect(controller.viewModel.hasLoadedDocument)

        controller.confirmCloseCurrentDocument = { _ in false }
        controller.closeCurrentDocument()

        #expect(controller.viewModel.hasLoadedDocument)
        #expect(controller.viewModel.currentFileURL == fixtureURL)

        controller.confirmCloseCurrentDocument = { _ in true }
        controller.closeCurrentDocument()

        #expect(controller.viewModel.hasLoadedDocument == false)
        #expect(controller.viewModel.currentFileURL == nil)
        #expect(controller.viewModel.browserOutlineRootNodes.isEmpty)
        #expect(controller.viewModel.browserDetailText.isEmpty)
    }

    @Test("close file clears a staged load that is still in progress")
    func closeFileClearsAStagedLoadThatIsStillInProgress() async throws {
        let fixtureURL = try makeEditableFixtureCopy()
        let budget = AnalysisBudget(
            maximumFileSize: 1,
            maximumSymbolCount: .max,
            maximumStringTableSize: .max,
            maximumEstimatedNodeCount: .max
        )
        let controller = MainWindowController(
            viewModel: WorkspaceViewModel(
                analysisBudget: budget,
                documentLoadService: WorkspaceDocumentLoadService { url, analysisBudget in
                    Thread.sleep(forTimeInterval: 0.2)
                    let scan = try MachOContainer.scan(at: url)
                    return WorkspaceDocumentLoadService.MetadataStage(
                        scan: scan,
                        decision: analysisBudget.classify(scan: scan),
                        analysis: try DocumentAnalysisService().analyze(scan: scan)
                    )
                }
            )
        )

        controller.confirmCloseCurrentDocument = { (_: NSWindow?) in true }

        #expect(controller.openDocument(at: fixtureURL))
        #expect(controller.viewModel.loadingState == WorkspaceViewModel.LoadingState.loading)
        #expect(controller.viewModel.hasLoadedDocument == false)
        #expect(controller.viewModel.currentFileURL == fixtureURL)

        controller.closeCurrentDocument()

        #expect(controller.viewModel.currentFileURL == nil)
        #expect(controller.viewModel.loadingState == WorkspaceViewModel.LoadingState.idle)
        #expect(controller.viewModel.loadingDetailText.isEmpty)
        #expect(controller.viewModel.browserDocument == nil)
        #expect(controller.viewModel.browserOutlineRootNodes.isEmpty)

        try? await Task.sleep(nanoseconds: 400_000_000)

        #expect(controller.viewModel.currentFileURL == nil)
        #expect(controller.viewModel.loadingState == WorkspaceViewModel.LoadingState.idle)
        #expect(controller.viewModel.browserDocument == nil)
    }

    @Test("close file clears stale loading copy after a staged document finishes loading")
    func closeFileClearsStaleLoadingCopyAfterAStagedDocumentFinishesLoading() async throws {
        let fixtureURL = try makeEditableFixtureCopy()
        let budget = AnalysisBudget(
            maximumFileSize: 1,
            maximumSymbolCount: .max,
            maximumStringTableSize: .max,
            maximumEstimatedNodeCount: .max
        )
        let scan = try MachOContainer.scan(at: fixtureURL)
        let metadataStage = WorkspaceDocumentLoadService.MetadataStage(
            scan: scan,
            decision: budget.classify(scan: scan),
            analysis: try DocumentAnalysisService().analyze(scan: scan)
        )
        let controller = MainWindowController(
            viewModel: WorkspaceViewModel(
                analysisBudget: budget,
                documentLoadService: WorkspaceDocumentLoadService { _, _ in metadataStage }
            )
        )
        _ = try #require(controller.window)
        controller.confirmCloseCurrentDocument = { (_: NSWindow?) in true }

        #expect(controller.openDocument(at: fixtureURL))

        let deadline = Date().addingTimeInterval(2)
        while controller.viewModel.browserDocument == nil, Date() < deadline {
            pumpRunLoop(for: 0.05)
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(controller.viewModel.browserDocument != nil)

        controller.closeCurrentDocument()
        pumpRunLoop(for: 0.2)

        let visibleTexts = visibleWindowTexts(in: controller.window)
        #expect(visibleTexts.contains(L10n.workspaceEmptyTitle))
        #expect(visibleTexts.contains(L10n.workspaceLoadingTitle) == false)
        #expect(visibleTexts.contains(L10n.workspaceLoadingAnalyzing) == false)
    }

    @Test("main and preferences windows refresh localized titles immediately after language changes")
    func windowsRefreshLocalizedTitlesImmediatelyAfterLanguageChanges() throws {
        let suiteName = "MachOKnifeTests.LocalizationRefresh.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        settings.language = .english

        let originalSettingsProvider = L10n.settingsProvider
        let originalBundleProvider = L10n.bundleProvider
        L10n.settingsProvider = { settings }
        L10n.bundleProvider = { .main }

        defer {
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

        _ = try #require(mainWindowController.window)
        _ = try #require(preferencesWindowController.window)

        #expect(mainWindowController.window?.title == "MachOKnife")
        #expect(preferencesWindowController.window?.title == "Preferences")

        settings.language = .simplifiedChinese
        pumpRunLoop(for: 0.2)

        #expect(preferencesWindowController.window?.title == "偏好设置")
        #expect(mainWindowController.window?.title == "MachOKnife")
    }

    @Test("preferences toolbar tabs keep icons and resize to the selected content")
    func preferencesTabsKeepIconsAndResizeWindow() throws {
        let suiteName = "MachOKnifeTests.LocalizationRefresh.Preferences.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let updateManager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(feedURLString: "", publicEDKey: "")
            },
            clientProvider: { nil }
        )
        let controller = PreferencesWindowController(
            settings: AppSettings(defaults: defaults),
            updateManager: updateManager
        )
        controller.window?.setFrame(NSRect(x: 0, y: 0, width: 680, height: 460), display: true)

        controller.present(nil)
        pumpRunLoop(for: 0.3)

        let tabController = try #require(controller.window?.contentViewController as? NSTabViewController)
        #expect(tabController.tabViewItems.allSatisfy { $0.image != nil })
        #expect(controller.window?.toolbarStyle == .preference)

        let originalWidth = try #require(controller.window?.frame.width)
        let originalHeight = try #require(controller.window?.frame.height)
        controller.window?.setFrame(
            NSRect(x: 0, y: 0, width: originalWidth + 120, height: originalHeight),
            display: true
        )
        pumpRunLoop(for: 0.2)
        let widenedWidth = try #require(controller.window?.frame.width)
        controller.selectTab(at: 2)
        pumpRunLoop(for: 0.3)
        let appearanceWidth = try #require(controller.window?.frame.width)
        let appearanceHeight = try #require(controller.window?.frame.height)

        controller.selectTab(at: 0)
        pumpRunLoop(for: 0.3)
        let generalWidth = try #require(controller.window?.frame.width)
        let generalHeight = try #require(controller.window?.frame.height)
        let generalContentHeight = try #require(controller.window?.contentRect(forFrameRect: controller.window!.frame).height)

        #expect(widenedWidth > originalWidth)
        #expect(widenedWidth == appearanceWidth)
        #expect(widenedWidth == generalWidth)
        #expect(appearanceHeight != generalHeight)
        #expect(originalHeight != appearanceHeight || originalHeight != generalHeight)
        #expect(generalContentHeight < 150)

        controller.selectTab(at: 2)
        pumpRunLoop(for: 0.3)
        let appearanceContentHeight = try #require(controller.window?.contentRect(forFrameRect: controller.window!.frame).height)

        #expect(appearanceContentHeight < 100)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("dock reopen shows the main window without prompting for a file")
    func dockReopenShowsMainWindowWithoutPromptingForAFile() throws {
        let updateManager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(feedURLString: "", publicEDKey: "")
            },
            clientProvider: { nil }
        )
        let mainWindowController = SpyMainWindowController()
        let appDelegate = AppDelegate(
            settings: .shared,
            updateManager: updateManager,
            mainWindowControllerFactory: { mainWindowController }
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        mainWindowController.resetCounts()

        _ = appDelegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)

        #expect(mainWindowController.presentCallCount == 1)
        #expect(mainWindowController.promptCallCount == 0)
    }

    @Test("CLI preferences refresh the last action text after language changes")
    func cliPreferencesRefreshLastActionTextAfterLanguageChanges() throws {
        let suiteName = "MachOKnifeTests.LocalizationRefresh.CLI.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        settings.language = .english

        let installDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let installedCLIURL = installDirectory.appendingPathComponent("machoe-cli")
        let installService = StubLocalizedCLIInstallService(
            status: CLIInstallStatus(
                installDirectoryURL: installDirectory,
                installedCLIURL: installedCLIURL,
                isInstalled: false
            ),
            installedStatus: CLIInstallStatus(
                installDirectoryURL: installDirectory,
                installedCLIURL: installedCLIURL,
                isInstalled: true
            )
        )

        let originalSettingsProvider = L10n.settingsProvider
        let originalBundleProvider = L10n.bundleProvider
        L10n.settingsProvider = { settings }
        L10n.bundleProvider = { .main }

        defer {
            L10n.settingsProvider = originalSettingsProvider
            L10n.bundleProvider = originalBundleProvider
            defaults.removePersistentDomain(forName: suiteName)
        }

        let controller = CLIPreferencesViewController(settings: settings, installService: installService)
        controller.loadViewIfNeeded()

        let installButton = try #require(mirrorValue(named: "installButton", from: controller) as? NSButton)
        let lastActionLabel = try #require(mirrorValue(named: "lastActionValueLabel", from: controller) as? NSTextField)

        installButton.performClick(nil)
        #expect(lastActionLabel.stringValue == L10n.preferencesCLISuccessInstall(path: installedCLIURL.path))

        settings.language = .simplifiedChinese
        pumpRunLoop(for: 0.2)

        #expect(lastActionLabel.stringValue == L10n.preferencesCLISuccessInstall(path: installedCLIURL.path))
    }

    @Test("CLI preferences show feedback when install completes without an installed state")
    func cliPreferencesShowFeedbackWhenInstallDoesNotReachInstalledState() throws {
        let suiteName = "MachOKnifeTests.LocalizationRefresh.CLI.Pending.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettings(defaults: defaults)
        let installDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let installService = StubLocalizedCLIInstallService(
            status: CLIInstallStatus(
                installDirectoryURL: installDirectory,
                installedCLIURL: installDirectory.appendingPathComponent("machoe-cli"),
                isInstalled: false
            ),
            installedStatus: CLIInstallStatus(
                installDirectoryURL: installDirectory,
                installedCLIURL: installDirectory.appendingPathComponent("machoe-cli"),
                isInstalled: false
            )
        )

        let controller = CLIPreferencesViewController(settings: settings, installService: installService)
        controller.loadViewIfNeeded()

        let installButton = try #require(mirrorValue(named: "installButton", from: controller) as? NSButton)
        let lastActionLabel = try #require(mirrorValue(named: "lastActionValueLabel", from: controller) as? NSTextField)

        #expect(lastActionLabel.stringValue == L10n.preferencesCLILastActionIdle)

        installButton.performClick(nil)

        #expect(lastActionLabel.stringValue != L10n.preferencesCLILastActionIdle)
    }

    @Test("workspace detail text refreshes localized labels immediately after language changes")
    func workspaceDetailTextRefreshesImmediatelyAfterLanguageChanges() throws {
        let suiteName = "MachOKnifeTests.LocalizationRefresh.Workspace.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        settings.language = .english

        let originalSettingsProvider = L10n.settingsProvider
        let originalBundleProvider = L10n.bundleProvider
        L10n.settingsProvider = { settings }
        L10n.bundleProvider = { .main }

        defer {
            L10n.settingsProvider = originalSettingsProvider
            L10n.bundleProvider = originalBundleProvider
            defaults.removePersistentDomain(forName: suiteName)
        }

        let controller = MainWindowController()
        let fixtureURL = try makeEditableFixtureCopy()

        #expect(controller.openDocument(at: fixtureURL))
        controller.viewModel.select(.slice(0))
        #expect(controller.viewModel.detailText.contains("File Offset"))

        settings.language = .simplifiedChinese
        pumpRunLoop(for: 0.2)

        #expect(controller.viewModel.detailText.contains("文件偏移"))
    }

    @Test("retag window refreshes localized title immediately after language changes")
    func retagWindowRefreshesImmediatelyAfterLanguageChanges() throws {
        let suiteName = "MachOKnifeTests.LocalizationRefresh.Retag.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        settings.language = .english

        let originalSettingsProvider = L10n.settingsProvider
        let originalBundleProvider = L10n.bundleProvider
        L10n.settingsProvider = { settings }
        L10n.bundleProvider = { .main }

        defer {
            L10n.settingsProvider = originalSettingsProvider
            L10n.bundleProvider = originalBundleProvider
            defaults.removePersistentDomain(forName: suiteName)
        }

        let controller = RetagWindowController()
        controller.present(nil)
        pumpRunLoop(for: 0.2)

        #expect(controller.window?.title == "Retag Tool")

        settings.language = .simplifiedChinese
        pumpRunLoop(for: 0.2)

        #expect(controller.window?.title == "Retag 工具")
    }

    @Test("app delegate rebuilds menus safely when appearance and language change")
    func appDelegateRebuildsMenusSafelyAcrossSettingsChanges() throws {
        let suiteName = "MachOKnifeTests.LocalizationRefresh.AppDelegate.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        settings.language = .english
        settings.theme = .light

        let originalSettingsProvider = L10n.settingsProvider
        let originalBundleProvider = L10n.bundleProvider
        let originalMainMenu = NSApp.mainMenu
        let originalAppearance = NSApp.appearance
        let existingWindows = NSApp.windows
        L10n.settingsProvider = { settings }
        L10n.bundleProvider = { .main }

        defer {
            L10n.settingsProvider = originalSettingsProvider
            L10n.bundleProvider = originalBundleProvider
            NSApp.mainMenu = originalMainMenu
            NSApp.appearance = originalAppearance
            for window in NSApp.windows where existingWindows.contains(where: { $0 === window }) == false {
                window.close()
            }
            defaults.removePersistentDomain(forName: suiteName)
        }

        let updateManager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(feedURLString: "", publicEDKey: "")
            },
            clientProvider: { nil }
        )

        let appDelegate = AppDelegate(settings: settings, updateManager: updateManager)
        let preferencesController = PreferencesWindowController(settings: settings, updateManager: updateManager)
        let retagController = RetagWindowController()
        preferencesController.present(nil)
        retagController.present(nil)
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        pumpRunLoop(for: 0.2)

        let originalRecentMenu = try #require(currentRecentFilesMenu())
        #expect(fileMenu() != nil)

        settings.theme = .dark
        pumpRunLoop(for: 0.2)

        let darkRecentMenu = try #require(currentRecentFilesMenu())
        #expect(originalRecentMenu !== darkRecentMenu)
        #expect(NSApp.appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)

        settings.language = .simplifiedChinese
        pumpRunLoop(for: 0.2)

        let localizedRecentMenu = try #require(currentRecentFilesMenu())
        let localizedFileMenu = try #require(topLevelMenu(title: "文件"))
        let toolsMenu = try #require(topLevelMenu(title: "工具"))
        let helpMenu = try #require(topLevelMenu(title: "帮助"))

        #expect(darkRecentMenu !== localizedRecentMenu)
        #expect(localizedFileMenu.title == "文件")
        #expect(toolsMenu.title == "工具")
        #expect(helpMenu.title == "帮助")
    }

    @Test("file menu exposes Finder and path actions for the current document")
    func fileMenuExposesFinderAndPathActionsForCurrentDocument() throws {
        let controller = MainWindowController()
        let fixtureURL = try makeEditableFixtureCopy()

        #expect(controller.openDocument(at: fixtureURL))

        let updateManager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(feedURLString: "", publicEDKey: "")
            },
            clientProvider: { nil }
        )
        let appDelegate = AppDelegate(settings: .shared, updateManager: updateManager)
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        pumpRunLoop(for: 0.2)

        let currentFileMenu = try #require(fileMenu())
        #expect(currentFileMenu.items.contains(where: { $0.title == L10n.menuShowCurrentFileInFinder }))
        #expect(currentFileMenu.items.contains(where: { $0.title == L10n.menuCopyFilePath }))
    }

    private func pumpRunLoop(for duration: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }

    private func visibleWindowTexts(in window: NSWindow?) -> [String] {
        guard let contentView = window?.contentView else { return [] }
        return collectVisibleTexts(in: contentView)
    }

    private func collectVisibleTexts(in view: NSView) -> [String] {
        guard view.isHidden == false else { return [] }

        var texts: [String] = []
        if let textField = view as? NSTextField {
            let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty == false {
                texts.append(text)
            }
        } else if let button = view as? NSButton {
            let text = button.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty == false {
                texts.append(text)
            }
        }

        for subview in view.subviews {
            texts.append(contentsOf: collectVisibleTexts(in: subview))
        }
        return texts
    }

    private func mirrorValue(named name: String, from object: Any) -> Any? {
        Mirror(reflecting: object).children.first { $0.label == name }?.value
    }

    private func topLevelMenu(title: String) -> NSMenu? {
        NSApp.mainMenu?.items.compactMap(\.submenu).first { $0.title == title }
    }

    private func fileMenu() -> NSMenu? {
        NSApp.mainMenu?.items
            .compactMap(\.submenu)
            .first { menu in
                menu.items.contains(where: { $0.keyEquivalent == "o" })
                    && menu.items.contains(where: { $0.keyEquivalent == "w" })
            }
    }

    private func currentRecentFilesMenu() -> NSMenu? {
        fileMenu()?.items.first(where: { $0.submenu != nil })?.submenu
    }

    private func makeEditableFixtureCopy() throws -> URL {
        let sourceURL = repoRoot()
            .appendingPathComponent("Resources")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("cli")
            .appendingPathComponent("libCLIEditable.dylib")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destinationURL = directory.appendingPathComponent("libCLIEditable.dylib")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func repoRoot(fileURL: URL = URL(filePath: #filePath)) -> URL {
        fileURL.deletingLastPathComponent().deletingLastPathComponent()
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private final class StubLocalizedCLIInstallService: CLIInstallServicing {
    private let currentStatus: CLIInstallStatus
    private let installedStatus: CLIInstallStatus

    init(status: CLIInstallStatus, installedStatus: CLIInstallStatus) {
        self.currentStatus = status
        self.installedStatus = installedStatus
    }

    func status() throws -> CLIInstallStatus {
        currentStatus
    }

    func install() throws -> CLIInstallStatus {
        installedStatus
    }

    func uninstall() throws -> CLIInstallStatus {
        currentStatus
    }
}

@MainActor
private final class SpyMainWindowController: MainWindowControlling {
    var onDocumentOpened: ((URL) -> Void)?
    var window: NSWindow?
    var hasLoadedDocument = false
    var canCopyOrExportSelectedNodeInfo = false
    var hasCurrentFileURL = false
    private(set) var presentCallCount = 0
    private(set) var promptCallCount = 0

    func present(_ sender: Any?) {
        presentCallCount += 1
    }

    func promptForDocument(_ sender: Any?) {
        promptCallCount += 1
    }

    func openDocument(at url: URL) -> Bool { false }
    func closeCurrentDocument() {}
    func reloadLocalization() {}
    func showCurrentFileInFinder() {}
    func copyCurrentFilePath() {}
    func copySelectedNodeInfo() {}
    func exportSelectedNodeInfo() {}

    func resetCounts() {
        presentCallCount = 0
        promptCallCount = 0
    }
}

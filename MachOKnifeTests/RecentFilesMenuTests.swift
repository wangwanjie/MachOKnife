import AppKit
import Foundation
import Testing
@testable import MachOKnife

/// File > Open Recent 菜单底部“清除菜单”项的测试。
@MainActor
struct RecentFilesMenuTests {
    @Test("open recent lists files followed by a Clear Menu item that empties the list")
    func clearMenuEmptiesRecentFiles() throws {
        let localization = TestLocalizationOverride(language: .english)
        defer {
            localization.restore()
        }
        let recentFilesController = try makeRecentFilesController()
        let firstURL = try TestUI.makeFixtureCopy(named: "RecentA.dylib")
        let secondURL = try TestUI.makeFixtureCopy(named: "RecentB.dylib")
        try recentFilesController.recordOpen(url: firstURL, openedAt: Date(timeIntervalSince1970: 10))
        try recentFilesController.recordOpen(url: secondURL, openedAt: Date(timeIntervalSince1970: 20))

        let appDelegate = makeLaunchedAppDelegate(recentFilesController: recentFilesController)
        let menu = appDelegate.openRecentMenu

        #expect(menu.items.map(\.title) == ["RecentB.dylib", "RecentA.dylib", "", L10n.menuOpenRecentClear])
        #expect(menu.items[2].isSeparatorItem)
        let clearItem = try #require(menu.items.last)
        #expect(clearItem.isEnabled)

        let action = try #require(clearItem.action)
        #expect(NSApp.sendAction(action, to: clearItem.target, from: clearItem))

        #expect(try recentFilesController.recentFileURLs().isEmpty)
        // 清空后菜单立即刷新为“没有最近文件”的占位项，且不再显示“清除菜单”。
        let refreshedMenu = appDelegate.openRecentMenu
        #expect(refreshedMenu.items.map(\.title) == [L10n.menuOpenRecentEmpty])
        #expect(refreshedMenu.items.first?.isEnabled == false)
    }

    @Test("an empty recent files list shows only the placeholder item")
    func emptyRecentFilesShowsPlaceholderOnly() throws {
        let localization = TestLocalizationOverride(language: .english)
        defer {
            localization.restore()
        }
        let appDelegate = makeLaunchedAppDelegate(recentFilesController: try makeRecentFilesController())

        #expect(appDelegate.openRecentMenu.items.map(\.title) == [L10n.menuOpenRecentEmpty])
    }

    // MARK: - Helpers

    private func makeLaunchedAppDelegate(recentFilesController: RecentFilesController) -> AppDelegate {
        let updateManager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(feedURLString: "", publicEDKey: "")
            },
            clientProvider: { nil }
        )
        let appDelegate = AppDelegate(
            settings: .shared,
            updateManager: updateManager,
            mainWindowControllerFactory: { RecentFilesMenuSpyMainWindowController() },
            recentFilesControllerFactory: { _ in recentFilesController }
        )
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        return appDelegate
    }

    /// 使用独立的临时数据库和 UserDefaults，避免影响真实的最近文件列表。
    private func makeRecentFilesController() throws -> RecentFilesController {
        let suiteName = "RecentFilesMenuTests.\(UUID().uuidString)"
        let settingsDefaults = UserDefaults(suiteName: suiteName)!
        settingsDefaults.removePersistentDomain(forName: suiteName)
        let bookmarkSuiteName = "\(suiteName).bookmarks"
        let bookmarkDefaults = UserDefaults(suiteName: bookmarkSuiteName)!
        bookmarkDefaults.removePersistentDomain(forName: bookmarkSuiteName)
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("RecentFiles.sqlite")
        return try RecentFilesController(
            settings: AppSettings(defaults: settingsDefaults),
            databaseURL: databaseURL,
            defaults: bookmarkDefaults,
            bookmarkDataProvider: { _ in
                throw CocoaError(.fileNoSuchFile)
            }
        )
    }
}

@MainActor
private final class RecentFilesMenuSpyMainWindowController: MainWindowControlling {
    var onDocumentOpened: ((URL) -> Void)?
    var window: NSWindow?
    var hasLoadedDocument = false
    var canCopyOrExportSelectedNodeInfo = false
    var hasCurrentFileURL = false
    var loadedDocumentURL: URL?

    func present(_ sender: Any?) {}
    func promptForDocument(_ sender: Any?) {}
    func openDocument(at url: URL) -> Bool { false }
    func closeCurrentDocument() {}
    func reloadLocalization() {}
    func showCurrentFileInFinder() {}
    func copyCurrentFilePath() {}
    func copySelectedNodeInfo() {}
    func exportSelectedNodeInfo() {}
}

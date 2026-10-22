import AppKit
import Foundation
import Testing
@testable import MachOKnife

/// 工作区 → 工具窗口文件交接的测试：纯逻辑规则 + 通过 Tools 菜单打开工具窗口的端到端行为。
@MainActor
struct WorkspaceToolHandOffTests {
    // MARK: - 交接规则

    @Test("an empty tool input is pre-filled with the workspace document")
    func emptyInputIsPrefilled() {
        var handOff = WorkspaceToolHandOff()
        let documentURL = URL(filePath: "/tmp/handoff/A.dylib")

        #expect(handOff.inputToPrefill(workspaceDocumentURL: documentURL, currentInputURL: nil) == documentURL)
        #expect(handOff.lastHandedOffURL == documentURL)
    }

    @Test("no workspace document leaves the tool input unchanged")
    func noWorkspaceDocumentLeavesInputUnchanged() {
        var handOff = WorkspaceToolHandOff()

        #expect(handOff.inputToPrefill(workspaceDocumentURL: nil, currentInputURL: nil) == nil)
        #expect(handOff.inputToPrefill(workspaceDocumentURL: nil, currentInputURL: URL(filePath: "/tmp/x")) == nil)
        #expect(handOff.lastHandedOffURL == nil)
    }

    @Test("the same file is not reloaded")
    func sameFileIsNotReloaded() {
        var handOff = WorkspaceToolHandOff()
        let documentURL = URL(filePath: "/tmp/handoff/A.dylib")

        _ = handOff.inputToPrefill(workspaceDocumentURL: documentURL, currentInputURL: nil)
        // 路径写法不同但指向同一文件时同样视为相同。
        let equivalentURL = URL(filePath: "/tmp/handoff/./A.dylib")
        #expect(handOff.inputToPrefill(workspaceDocumentURL: equivalentURL, currentInputURL: documentURL) == nil)
    }

    @Test("a handed-off input follows the workspace when another document is opened")
    func handedOffInputFollowsWorkspace() {
        var handOff = WorkspaceToolHandOff()
        let firstURL = URL(filePath: "/tmp/handoff/A.dylib")
        let secondURL = URL(filePath: "/tmp/handoff/B.dylib")

        _ = handOff.inputToPrefill(workspaceDocumentURL: firstURL, currentInputURL: nil)

        #expect(handOff.inputToPrefill(workspaceDocumentURL: secondURL, currentInputURL: firstURL) == secondURL)
        #expect(handOff.lastHandedOffURL == secondURL)
    }

    @Test("a file the user chose in the tool is never overwritten")
    func userChosenInputIsKept() {
        var handOff = WorkspaceToolHandOff()
        let documentURL = URL(filePath: "/tmp/handoff/A.dylib")
        let userURL = URL(filePath: "/tmp/handoff/User.dylib")

        #expect(handOff.inputToPrefill(workspaceDocumentURL: documentURL, currentInputURL: userURL) == nil)

        // 即使之前交接过，用户之后手动换成的文件也要保留。
        _ = handOff.inputToPrefill(workspaceDocumentURL: documentURL, currentInputURL: nil)
        let nextDocumentURL = URL(filePath: "/tmp/handoff/B.dylib")
        #expect(handOff.inputToPrefill(workspaceDocumentURL: nextDocumentURL, currentInputURL: userURL) == nil)
    }

    // MARK: - Tools 菜单集成

    @Test("tools opened from the menu are pre-filled with the loaded workspace document")
    func toolsArePrefilledWithWorkspaceDocument() throws {
        let localization = TestLocalizationOverride(language: .english)
        defer {
            localization.restore()
        }
        let documentURL = try TestUI.makeFixtureCopy()
        let mainWindowController = HandOffSpyMainWindowController()
        mainWindowController.loadedDocumentURL = documentURL
        let appDelegate = makeLaunchedAppDelegate(mainWindowController: mainWindowController)
        defer {
            closeToolWindows(of: appDelegate)
        }

        try performToolsMenuItem(titled: L10n.menuMachOSummary)
        try performToolsMenuItem(titled: L10n.menuCheckBinaryContamination)
        try performToolsMenuItem(titled: L10n.menuRetag)
        try performToolsMenuItem(titled: L10n.menuMergeSplitMachO)

        #expect(appDelegate.machoSummaryWindowController?.inputURL == documentURL)
        #expect(appDelegate.contaminationWindowController?.inputURL == documentURL)
        #expect(appDelegate.retagWindowController?.inputURL == documentURL)
        let mergeSplit = try #require(appDelegate.mergeSplitWindowController)
        #expect(mergeSplit.splitInputURL == documentURL)
        #expect(mergeSplit.removeArchitecturesViewModel.inputURL == documentURL)
        // 测试样本是单架构 dylib：表单载入后应识别出没有可移除的架构，而不是弹窗报错。
        #expect(mergeSplit.removeArchitecturesViewModel.availableArchitectures.count == 1)
        #expect(mergeSplit.removeArchitecturesViewModel.hasRemovableArchitectures == false)
    }

    @Test("tools keep their empty state when no workspace document is open")
    func toolsStayEmptyWithoutWorkspaceDocument() throws {
        let localization = TestLocalizationOverride(language: .english)
        defer {
            localization.restore()
        }
        let mainWindowController = HandOffSpyMainWindowController()
        let appDelegate = makeLaunchedAppDelegate(mainWindowController: mainWindowController)
        defer {
            closeToolWindows(of: appDelegate)
        }

        try performToolsMenuItem(titled: L10n.menuMachOSummary)
        try performToolsMenuItem(titled: L10n.menuCheckBinaryContamination)
        try performToolsMenuItem(titled: L10n.menuRetag)
        try performToolsMenuItem(titled: L10n.menuMergeSplitMachO)

        #expect(appDelegate.machoSummaryWindowController?.inputURL == nil)
        #expect(appDelegate.contaminationWindowController?.inputURL == nil)
        #expect(appDelegate.retagWindowController?.inputURL == nil)
        #expect(appDelegate.mergeSplitWindowController?.splitInputURL == nil)
        #expect(appDelegate.mergeSplitWindowController?.removeArchitecturesViewModel.inputURL == nil)
    }

    @Test("reopening a tool follows the workspace but keeps a file the user picked")
    func reopeningToolFollowsWorkspaceButKeepsUserChoice() throws {
        let localization = TestLocalizationOverride(language: .english)
        defer {
            localization.restore()
        }
        let firstURL = try TestUI.makeFixtureCopy(named: "First.dylib")
        let secondURL = try TestUI.makeFixtureCopy(named: "Second.dylib")
        let userURL = try TestUI.makeFixtureCopy(named: "UserPicked.dylib")
        let mainWindowController = HandOffSpyMainWindowController()
        mainWindowController.loadedDocumentURL = firstURL
        let appDelegate = makeLaunchedAppDelegate(mainWindowController: mainWindowController)
        defer {
            closeToolWindows(of: appDelegate)
        }

        try performToolsMenuItem(titled: L10n.menuMachOSummary)
        let summary = try #require(appDelegate.machoSummaryWindowController)
        #expect(summary.inputURL == firstURL)

        // 工作区换了文件，且工具输入仍是上次交接的文件：重新打开时跟随工作区。
        mainWindowController.loadedDocumentURL = secondURL
        try performToolsMenuItem(titled: L10n.menuMachOSummary)
        #expect(summary.inputURL == secondURL)

        // 用户在工具里手动换了文件：之后再打开也不覆盖。
        summary.loadInput(userURL)
        mainWindowController.loadedDocumentURL = firstURL
        try performToolsMenuItem(titled: L10n.menuMachOSummary)
        #expect(summary.inputURL == userURL)
    }

    // MARK: - Helpers

    private func makeLaunchedAppDelegate(mainWindowController: HandOffSpyMainWindowController) -> AppDelegate {
        let updateManager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(feedURLString: "", publicEDKey: "")
            },
            clientProvider: { nil }
        )
        let appDelegate = AppDelegate(
            settings: .shared,
            updateManager: updateManager,
            mainWindowControllerFactory: { mainWindowController },
            recentFilesControllerFactory: { _ in nil }
        )
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        return appDelegate
    }

    /// 通过 Tools 菜单项触发动作，与用户点击菜单走同一条路径。
    private func performToolsMenuItem(titled title: String) throws {
        let toolsMenu = try #require(
            NSApp.mainMenu?.items
                .compactMap(\.submenu)
                .first(where: { $0.title == L10n.menuTools })
        )
        let item = try #require(toolsMenu.items.first(where: { $0.title == title }))
        let action = try #require(item.action)
        #expect(NSApp.sendAction(action, to: item.target, from: item))
    }

    private func closeToolWindows(of appDelegate: AppDelegate) {
        appDelegate.machoSummaryWindowController?.window?.close()
        appDelegate.contaminationWindowController?.window?.close()
        appDelegate.retagWindowController?.window?.close()
        appDelegate.mergeSplitWindowController?.window?.close()
    }
}

@MainActor
private final class HandOffSpyMainWindowController: MainWindowControlling {
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

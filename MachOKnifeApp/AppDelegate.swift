import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: AppSettings
    private let updateManager: UpdateManager
    private let mainWindowControllerFactory: () -> MainWindowControlling
    private lazy var recentFilesController = try? RecentFilesController(settings: settings)
    private var mainWindowController: MainWindowControlling?
    private var preferencesWindowController: PreferencesWindowController?
    private var retagWindowController: RetagWindowController?
    private var xcframeworkBuildWindowController: XCFrameworkBuildWindowController?
    private var machoSummaryWindowController: MachOSummaryWindowController?
    private var contaminationWindowController: BinaryContaminationWindowController?
    private var mergeSplitWindowController: MachOMergeSplitWindowController?
    private var settingsObserver: NSObjectProtocol?
    private var recentFilesMenu = NSMenu(title: "")
    private var pendingLaunchDocumentURLs: [URL] = []

    override init() {
        self.settings = .shared
        self.updateManager = UpdateManager()
        self.mainWindowControllerFactory = { MainWindowController() }
        super.init()
    }

    init(
        settings: AppSettings,
        updateManager: UpdateManager,
        mainWindowControllerFactory: (() -> MainWindowControlling)? = nil
    ) {
        self.settings = settings
        self.updateManager = updateManager
        self.mainWindowControllerFactory = mainWindowControllerFactory ?? { MainWindowController() }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        applyAppearance()
        observeSettings()

        let mainWindowController = mainWindowControllerFactory()
        mainWindowController.onDocumentOpened = { [weak self] url in
            self?.recordRecentFile(url)
        }
        self.mainWindowController = mainWindowController
        mainWindowController.present(nil)

        let pendingLaunchDocumentURLs = self.pendingLaunchDocumentURLs
        self.pendingLaunchDocumentURLs = []
        for url in pendingLaunchDocumentURLs {
            _ = mainWindowController.openDocument(at: url)
        }

        refreshRecentFilesMenu()
        updateManager.performLaunchCheckIfNeeded()
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        showMainWindow(nil)
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard filenames.isEmpty == false else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        // The workspace shows one document at a time, so files are opened in order and the last
        // one stays visible; every file still goes through the normal open (and recents) flow.
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        guard let mainWindowController else {
            pendingLaunchDocumentURLs.append(contentsOf: urls)
            sender.reply(toOpenOrPrint: .success)
            return
        }

        var openedCount = 0
        for url in urls where mainWindowController.openDocument(at: url) {
            openedCount += 1
        }
        sender.reply(toOpenOrPrint: openedCount == urls.count ? .success : .failure)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc private func openDocument(_ sender: Any?) {
        mainWindowController?.present(sender)
        mainWindowController?.promptForDocument(sender)
    }

    @objc private func closeDocument(_ sender: Any?) {
        guard
            let mainWindow = mainWindowController?.window,
            NSApp.keyWindow === mainWindow || NSApp.mainWindow === mainWindow
        else {
            return
        }

        mainWindowController?.closeCurrentDocument()
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard
            let url = sender.representedObject as? URL,
            let mainWindowController
        else {
            return
        }

        _ = mainWindowController.openDocument(at: url)
    }

    @objc private func showMainWindow(_ sender: Any?) {
        mainWindowController?.present(sender)
    }

    @objc private func showPreferences(_ sender: Any?) {
        let preferencesWindowController = preferencesWindowController
            ?? PreferencesWindowController(settings: settings, updateManager: updateManager)
        self.preferencesWindowController = preferencesWindowController
        preferencesWindowController.present(sender)
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        updateManager.checkForUpdates()
    }

    @objc private func openGitHubHomepage(_ sender: Any?) {
        updateManager.openGitHubHomepage()
    }

    @objc private func showRetagTool(_ sender: Any?) {
        let retagWindowController = retagWindowController ?? RetagWindowController()
        self.retagWindowController = retagWindowController
        retagWindowController.present(sender)
    }

    @objc private func showXCFrameworkBuilder(_ sender: Any?) {
        let controller = xcframeworkBuildWindowController ?? XCFrameworkBuildWindowController()
        xcframeworkBuildWindowController = controller
        controller.present(sender)
    }

    @objc private func showMachOSummaryTool(_ sender: Any?) {
        let controller = machoSummaryWindowController ?? MachOSummaryWindowController()
        machoSummaryWindowController = controller
        controller.present(sender)
    }

    @objc private func showContaminationTool(_ sender: Any?) {
        let controller = contaminationWindowController ?? BinaryContaminationWindowController()
        contaminationWindowController = controller
        controller.present(sender)
    }

    @objc private func showMergeSplitTool(_ sender: Any?) {
        let controller = mergeSplitWindowController ?? MachOMergeSplitWindowController()
        mergeSplitWindowController = controller
        controller.present(sender)
    }

    @objc private func copySelectedNodeInfo(_ sender: Any?) {
        mainWindowController?.copySelectedNodeInfo()
    }

    @objc private func exportSelectedNodeInfo(_ sender: Any?) {
        mainWindowController?.exportSelectedNodeInfo()
    }

    @objc private func showCurrentFileInFinder(_ sender: Any?) {
        mainWindowController?.showCurrentFileInFinder()
    }

    @objc private func copyCurrentFilePath(_ sender: Any?) {
        mainWindowController?.copyCurrentFilePath()
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let recentFilesMenu = NSMenu(title: L10n.menuOpenRecent)
        self.recentFilesMenu = recentFilesMenu

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: L10n.menuAbout(), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        let preferencesItem = NSMenuItem(title: L10n.menuPreferences, action: #selector(showPreferences(_:)), keyEquivalent: ",")
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)
        let updatesItem = NSMenuItem(title: L10n.menuCheckForUpdates, action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        updatesItem.target = self
        appMenu.addItem(updatesItem)
        appMenu.addItem(NSMenuItem.separator())
        let servicesMenu = NSMenu(title: L10n.menuServices)
        let servicesItem = NSMenuItem(title: L10n.menuServices, action: nil, keyEquivalent: "")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: L10n.menuHide(), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthersItem = NSMenuItem(title: L10n.menuHideOthers, action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(NSMenuItem(title: L10n.menuShowAll, action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: L10n.menuQuit(), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: L10n.menuFile)
        let openItem = NSMenuItem(title: L10n.menuOpen, action: #selector(openDocument(_:)), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)
        let closeWindowItem = NSMenuItem(title: L10n.menuCloseWindow, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeWindowItem.target = nil
        closeWindowItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(closeWindowItem)
        let closeItem = NSMenuItem(title: L10n.menuCloseFile, action: #selector(closeDocument(_:)), keyEquivalent: "W")
        closeItem.target = self
        closeItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(closeItem)
        let showCurrentFileItem = NSMenuItem(title: L10n.menuShowCurrentFileInFinder, action: #selector(showCurrentFileInFinder(_:)), keyEquivalent: "r")
        showCurrentFileItem.target = self
        showCurrentFileItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(showCurrentFileItem)
        let copyFilePathItem = NSMenuItem(title: L10n.menuCopyFilePath, action: #selector(copyCurrentFilePath(_:)), keyEquivalent: "")
        copyFilePathItem.target = self
        fileMenu.addItem(copyFilePathItem)
        let exportNodeInfoItem = NSMenuItem(title: L10n.menuExportNodeInfo, action: #selector(exportSelectedNodeInfo(_:)), keyEquivalent: "e")
        exportNodeInfoItem.target = self
        exportNodeInfoItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(exportNodeInfoItem)
        let openRecentItem = NSMenuItem(title: L10n.menuOpenRecent, action: nil, keyEquivalent: "")
        openRecentItem.submenu = recentFilesMenu
        fileMenu.addItem(openRecentItem)
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L10n.menuEdit)
        // Standard editing items are nil-targeted so they reach the first responder
        // (text fields, text views, and the workspace tables).
        editMenu.addItem(NSMenuItem(title: L10n.menuUndo, action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: L10n.menuRedo, action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: L10n.menuCut, action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: L10n.menuCopy, action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: L10n.menuPaste, action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: L10n.menuDelete, action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(title: L10n.menuSelectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(NSMenuItem.separator())
        let copyNodeInfoItem = NSMenuItem(title: L10n.menuCopyNodeInfo, action: #selector(copySelectedNodeInfo(_:)), keyEquivalent: "c")
        copyNodeInfoItem.keyEquivalentModifierMask = [.command, .shift]
        copyNodeInfoItem.target = self
        editMenu.addItem(copyNodeInfoItem)
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let toolsItem = NSMenuItem()
        let toolsMenu = NSMenu(title: L10n.menuTools)
        let retagItem = NSMenuItem(title: L10n.menuRetag, action: #selector(showRetagTool(_:)), keyEquivalent: "t")
        retagItem.keyEquivalentModifierMask = [.command, .option]
        retagItem.target = self
        toolsMenu.addItem(retagItem)
        let xcframeworkItem = NSMenuItem(title: L10n.menuBuildXCFramework, action: #selector(showXCFrameworkBuilder(_:)), keyEquivalent: "x")
        xcframeworkItem.keyEquivalentModifierMask = [.command, .option]
        xcframeworkItem.target = self
        toolsMenu.addItem(xcframeworkItem)
        let summaryItem = NSMenuItem(title: L10n.menuMachOSummary, action: #selector(showMachOSummaryTool(_:)), keyEquivalent: "i")
        summaryItem.keyEquivalentModifierMask = [.command, .option]
        summaryItem.target = self
        toolsMenu.addItem(summaryItem)
        let contaminationItem = NSMenuItem(title: L10n.menuCheckBinaryContamination, action: #selector(showContaminationTool(_:)), keyEquivalent: "k")
        contaminationItem.keyEquivalentModifierMask = [.command, .option]
        contaminationItem.target = self
        toolsMenu.addItem(contaminationItem)
        let mergeSplitItem = NSMenuItem(title: L10n.menuMergeSplitMachO, action: #selector(showMergeSplitTool(_:)), keyEquivalent: "m")
        mergeSplitItem.keyEquivalentModifierMask = [.command, .option]
        mergeSplitItem.target = self
        toolsMenu.addItem(mergeSplitItem)
        toolsItem.submenu = toolsMenu
        mainMenu.addItem(toolsItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L10n.menuWindow)
        windowMenu.addItem(NSMenuItem(title: L10n.menuMinimize, action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: L10n.menuZoom, action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(NSMenuItem.separator())
        let showWindowItem = NSMenuItem(title: L10n.menuShowWorkspace, action: #selector(showMainWindow(_:)), keyEquivalent: "1")
        showWindowItem.target = self
        windowMenu.addItem(showWindowItem)
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(NSMenuItem(title: L10n.menuBringAllToFront, action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: L10n.menuHelp)
        let githubItem = NSMenuItem(title: L10n.menuGitHub, action: #selector(openGitHubHomepage(_:)), keyEquivalent: "?")
        githubItem.target = self
        helpMenu.addItem(githubItem)
        helpItem.submenu = helpMenu
        helpItem.title = L10n.menuHelp
        mainMenu.addItem(helpItem)

        replaceMainMenu(with: mainMenu)
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
    }

    private func applyAppearance() {
        NSApp.appearance = settings.effectiveAppearance()
    }

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue, so refresh synchronously instead of hopping through a Task.
            MainActor.assumeIsolated {
                guard let self else { return }

                // Windows (main, preferences, tools) observe this notification themselves and
                // reload their own localization; only app-level state is refreshed here.
                self.applyAppearance()
                self.buildMainMenu()
                self.refreshRecentFilesMenu()
            }
        }
    }

    private func recordRecentFile(_ url: URL) {
        try? recentFilesController?.recordOpen(url: url)
        refreshRecentFilesMenu()
    }

    private func refreshRecentFilesMenu() {
        recentFilesMenu.removeAllItems()

        let recentFiles = (try? recentFilesController?.recentFileURLs()) ?? []
        guard !recentFiles.isEmpty else {
            let emptyItem = NSMenuItem(title: L10n.menuOpenRecentEmpty, action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            recentFilesMenu.addItem(emptyItem)
            return
        }

        for url in recentFiles {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            recentFilesMenu.addItem(item)
        }
    }

    private func replaceMainMenu(with menu: NSMenu) {
        if let existingMainMenu = NSApp.mainMenu {
            detachMenuTree(existingMainMenu)
            NSApp.mainMenu = nil
        }
        NSApp.mainMenu = menu
    }

    private func detachMenuTree(_ menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu {
                detachMenuTree(submenu)
                item.submenu = nil
            }
        }
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(checkForUpdates(_:)):
            return updateManager.status().canCheckForUpdates
        case #selector(closeDocument(_:)):
            guard
                mainWindowController?.hasCurrentFileURL == true,
                let mainWindow = mainWindowController?.window
            else {
                return false
            }

            return NSApp.keyWindow === mainWindow || NSApp.mainWindow === mainWindow
        case #selector(showCurrentFileInFinder(_:)), #selector(copyCurrentFilePath(_:)):
            guard
                mainWindowController?.hasCurrentFileURL == true,
                let mainWindow = mainWindowController?.window
            else {
                return false
            }

            return NSApp.keyWindow === mainWindow || NSApp.mainWindow === mainWindow
        case #selector(copySelectedNodeInfo(_:)), #selector(exportSelectedNodeInfo(_:)):
            guard
                mainWindowController?.canCopyOrExportSelectedNodeInfo == true,
                let mainWindow = mainWindowController?.window
            else {
                return false
            }

            return NSApp.keyWindow === mainWindow || NSApp.mainWindow === mainWindow
        default:
            return true
        }
    }
}

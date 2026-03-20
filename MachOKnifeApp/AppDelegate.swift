import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private var mainWindowController: MainWindowController?
    private var preferencesWindowController: PreferencesWindowController?
    private var settingsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        applyAppearance()
        observeSettings()

        let mainWindowController = MainWindowController()
        self.mainWindowController = mainWindowController
        mainWindowController.present(nil)
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        openDocument(nil)
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let path = filenames.first else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        mainWindowController?.present(nil)
        mainWindowController?.openDocument(at: URL(fileURLWithPath: path))
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc private func openDocument(_ sender: Any?) {
        mainWindowController?.present(sender)
        mainWindowController?.promptForDocument(sender)
    }

    @objc private func reanalyzeDocument(_ sender: Any?) {
        mainWindowController?.reanalyzeCurrentDocument()
    }

    @objc private func showMainWindow(_ sender: Any?) {
        mainWindowController?.present(sender)
    }

    @objc private func showPreferences(_ sender: Any?) {
        let preferencesWindowController = preferencesWindowController ?? PreferencesWindowController(settings: settings)
        self.preferencesWindowController = preferencesWindowController
        preferencesWindowController.present(sender)
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: L10n.menuAbout(), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        let preferencesItem = NSMenuItem(title: L10n.menuPreferences, action: #selector(showPreferences(_:)), keyEquivalent: ",")
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: L10n.menuQuit(), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: L10n.menuFile)
        let openItem = NSMenuItem(title: L10n.menuOpen, action: #selector(openDocument(_:)), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)

        let analyzeItem = NSMenuItem(title: L10n.menuAnalyze, action: #selector(reanalyzeDocument(_:)), keyEquivalent: "r")
        analyzeItem.target = self
        fileMenu.addItem(analyzeItem)
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L10n.menuWindow)
        let showWindowItem = NSMenuItem(title: L10n.menuShowWorkspace, action: #selector(showMainWindow(_:)), keyEquivalent: "1")
        showWindowItem.target = self
        windowMenu.addItem(showWindowItem)
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    private func applyAppearance() {
        NSApp.appearance = settings.effectiveAppearance()
    }

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.didChangeNotification,
            object: settings,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyAppearance()
            }
        }
    }
}

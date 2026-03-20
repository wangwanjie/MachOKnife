import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        let mainWindowController = MainWindowController()
        self.mainWindowController = mainWindowController
        mainWindowController.present(nil)
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

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About MachOKnife", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit MachOKnife", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let openItem = NSMenuItem(title: "Open...", action: #selector(openDocument(_:)), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)

        let analyzeItem = NSMenuItem(title: "Analyze", action: #selector(reanalyzeDocument(_:)), keyEquivalent: "r")
        analyzeItem.target = self
        fileMenu.addItem(analyzeItem)
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let showWindowItem = NSMenuItem(title: "Show Workspace", action: #selector(showMainWindow(_:)), keyEquivalent: "1")
        showWindowItem.target = self
        windowMenu.addItem(showWindowItem)
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }
}

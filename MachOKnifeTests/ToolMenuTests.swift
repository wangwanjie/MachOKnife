import AppKit
import Testing
@testable import MachOKnife

@MainActor
struct ToolMenuTests {
    @Test("tools menu exposes summary inspection, contamination checking, and merge split actions")
    func toolsMenuExposesNewActions() throws {
        let updateManager = UpdateManager(
            configurationProvider: {
                UpdateConfiguration(feedURLString: "", publicEDKey: "")
            },
            clientProvider: { nil }
        )
        let appDelegate = AppDelegate(settings: .shared, updateManager: updateManager)
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        let toolsMenu = try #require(
            NSApp.mainMenu?.items
                .compactMap(\.submenu)
                .first(where: { $0.title == L10n.menuTools })
        )

        #expect(toolsMenu.items.contains(where: { $0.title == L10n.menuMachOSummary }))
        #expect(toolsMenu.items.contains(where: { $0.title == L10n.menuCheckBinaryContamination }))
        #expect(toolsMenu.items.contains(where: { $0.title == L10n.menuMergeSplitMachO }))
    }
}

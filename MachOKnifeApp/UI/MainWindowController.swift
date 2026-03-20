import AppKit

@MainActor
final class MainWindowController: NSWindowController {
    private static let autosaveName = NSWindow.FrameAutosaveName("MachOKnifeMainWindowFrame")

    let viewModel: WorkspaceViewModel
    private let splitViewController: WorkspaceSplitViewController

    convenience init() {
        self.init(viewModel: WorkspaceViewModel())
    }

    init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
        self.splitViewController = WorkspaceSplitViewController(viewModel: viewModel)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1420, height: 880),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.workspaceWindowTitle
        window.minSize = NSSize(width: 1180, height: 720)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        window.contentViewController = splitViewController

        super.init(window: window)

        splitViewController.promptForDocument = { [weak self] in
            self?.promptForDocument(nil)
        }

        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)
        window.setAccessibilityIdentifier("workspace.mainWindow")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(_ sender: Any?) {
        showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func promptForDocument(_ sender: Any?) {
        guard let window else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.title = L10n.openPanelTitle

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openDocument(at: url)
        }
    }

    func openDocument(at url: URL) {
        viewModel.openDocument(at: url)
        present(nil)
    }

    func reanalyzeCurrentDocument() {
        viewModel.reanalyzeCurrentDocument()
    }
}

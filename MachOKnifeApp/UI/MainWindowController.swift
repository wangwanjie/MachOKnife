import AppKit
import Combine

@MainActor
final class MainWindowController: NSWindowController, NSToolbarDelegate, NSToolbarItemValidation {
    private enum ToolbarItemIdentifier {
        static let analyze = NSToolbarItem.Identifier("machoknife.toolbar.analyze")
        static let preview = NSToolbarItem.Identifier("machoknife.toolbar.preview")
        static let save = NSToolbarItem.Identifier("machoknife.toolbar.save")
    }

    private static let autosaveName = NSWindow.FrameAutosaveName("MachOKnifeMainWindowFrame")

    let viewModel: WorkspaceViewModel
    var onDocumentOpened: ((URL) -> Void)?
    private let splitViewController: WorkspaceSplitViewController
    private var cancellables = Set<AnyCancellable>()

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

        window.toolbar = makeToolbar()

        splitViewController.promptForDocument = { [weak self] in
            self?.promptForDocument(nil)
        }
        splitViewController.openDocument = { [weak self] url in
            _ = self?.openDocument(at: url)
        }

        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)
        window.setAccessibilityIdentifier("workspace.mainWindow")

        bindViewModel()
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
            _ = self?.openDocument(at: url)
        }
    }

    @discardableResult
    func openDocument(at url: URL) -> Bool {
        let didOpen = viewModel.openDocument(at: url)
        if didOpen {
            onDocumentOpened?(url)
        }
        present(nil)
        window?.toolbar?.validateVisibleItems()
        return didOpen
    }

    func reanalyzeCurrentDocument() {
        viewModel.reanalyzeCurrentDocument()
        window?.toolbar?.validateVisibleItems()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItemIdentifier.analyze,
            ToolbarItemIdentifier.preview,
            ToolbarItemIdentifier.save,
            .flexibleSpace,
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItemIdentifier.analyze,
            ToolbarItemIdentifier.preview,
            .flexibleSpace,
            ToolbarItemIdentifier.save,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self

        switch itemIdentifier {
        case ToolbarItemIdentifier.analyze:
            item.label = L10n.toolbarAnalyze
            item.paletteLabel = L10n.toolbarAnalyze
            item.toolTip = L10n.toolbarAnalyze
            item.image = NSImage(systemSymbolName: "waveform.path.ecg.rectangle", accessibilityDescription: L10n.toolbarAnalyze)
            item.action = #selector(analyzeDocument(_:))
        case ToolbarItemIdentifier.preview:
            item.label = L10n.toolbarPreview
            item.paletteLabel = L10n.toolbarPreview
            item.toolTip = L10n.toolbarPreview
            item.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: L10n.toolbarPreview)
            item.action = #selector(previewEdits(_:))
        case ToolbarItemIdentifier.save:
            item.label = L10n.toolbarSave
            item.paletteLabel = L10n.toolbarSave
            item.toolTip = L10n.toolbarSave
            item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: L10n.toolbarSave)
            item.action = #selector(saveEdits(_:))
        default:
            return nil
        }

        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case ToolbarItemIdentifier.analyze:
            return viewModel.hasLoadedDocument
        case ToolbarItemIdentifier.preview, ToolbarItemIdentifier.save:
            return viewModel.hasLoadedDocument && viewModel.hasPendingEdits
        default:
            return true
        }
    }

    @objc private func analyzeDocument(_ sender: Any?) {
        reanalyzeCurrentDocument()
    }

    @objc private func previewEdits(_ sender: Any?) {
        do {
            try viewModel.previewEdits()
            splitViewController.selectPreviewInspectorTab()
        } catch {
            presentOperationError(error)
        }
    }

    @objc private func saveEdits(_ sender: Any?) {
        do {
            _ = try viewModel.saveEdits(createBackup: true)
            splitViewController.selectPreviewInspectorTab()
            window?.toolbar?.validateVisibleItems()
        } catch {
            presentOperationError(error)
        }
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "machoknife.main.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    private func bindViewModel() {
        Publishers.CombineLatest3(viewModel.$analysis, viewModel.$editableSlice, viewModel.$previewText)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.window?.toolbar?.validateVisibleItems()
            }
            .store(in: &cancellables)
    }

    private func presentOperationError(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

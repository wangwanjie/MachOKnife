import AppKit
import Combine
import MachOKnifeKit
import UniformTypeIdentifiers

@MainActor
protocol MainWindowControlling: AnyObject {
    var onDocumentOpened: ((URL) -> Void)? { get set }
    var window: NSWindow? { get }
    var hasLoadedDocument: Bool { get }
    var canCopyOrExportSelectedNodeInfo: Bool { get }
    var hasCurrentFileURL: Bool { get }

    func present(_ sender: Any?)
    func promptForDocument(_ sender: Any?)
    func openDocument(at url: URL) -> Bool
    func closeCurrentDocument()
    func reloadLocalization()
    func showCurrentFileInFinder()
    func copyCurrentFilePath()
    func copySelectedNodeInfo()
    func exportSelectedNodeInfo()
}

@MainActor
final class MainWindowController: NSWindowController {
    private static let autosaveName = NSWindow.FrameAutosaveName("MachOKnifeMainWindowFrame")

    let viewModel: WorkspaceViewModel
    var onDocumentOpened: ((URL) -> Void)?
    var confirmCloseCurrentDocument: ((NSWindow?) -> Bool)?
    private let splitViewController: WorkspaceSplitViewController
    private var cancellables = Set<AnyCancellable>()
    private var settingsObserver: NSObjectProtocol?
    private var activeSecurityScopedURL: URL?

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
        splitViewController.openDocument = { [weak self] url in
            _ = self?.openDocument(at: url)
        }
        splitViewController.copySelectedNodeInfo = { [weak self] in
            self?.copySelectedNodeInfo()
        }
        splitViewController.exportSelectedNodeInfo = { [weak self] in
            self?.exportSelectedNodeInfo()
        }

        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)
        window.setAccessibilityIdentifier("workspace.mainWindow")

        bindViewModel()
        observeSettings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
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
        let previousSecurityScopedURL = activeSecurityScopedURL
        let reuseExistingSecurityScope = previousSecurityScopedURL?.standardizedFileURL == url.standardizedFileURL
        let didAccessSecurityScope = reuseExistingSecurityScope ? false : url.startAccessingSecurityScopedResource()
        let didOpen = viewModel.openDocument(at: url)
        if didOpen {
            if reuseExistingSecurityScope == false {
                stopAccessingActiveSecurityScopedURL()
                activeSecurityScopedURL = didAccessSecurityScope ? url : nil
            }
            onDocumentOpened?(url)
        } else {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
            if reuseExistingSecurityScope == false {
                stopAccessingActiveSecurityScopedURL()
            }
        }
        present(nil)
        return didOpen
    }

    func reanalyzeCurrentDocument() {
        viewModel.reanalyzeCurrentDocument()
    }

    func closeCurrentDocument() {
        guard viewModel.currentFileURL != nil else { return }

        let shouldClose = confirmCloseCurrentDocument?(window) ?? presentCloseConfirmation()
        guard shouldClose else { return }

        viewModel.closeCurrentDocument()
        stopAccessingActiveSecurityScopedURL()
    }

    func reloadLocalization() {
        window?.title = L10n.workspaceWindowTitle
        splitViewController.reloadLocalization()
        viewModel.reloadPresentation()
    }

    var canCopyOrExportSelectedNodeInfo: Bool {
        viewModel.browserSelectedNode != nil
    }

    var hasLoadedDocument: Bool {
        viewModel.hasLoadedDocument
    }

    var hasCurrentFileURL: Bool {
        viewModel.currentFileURL != nil
    }

    func copySelectedNodeInfo() {
        guard let document = makeSelectedNodeInfoDocument() else { return }

        if document.lineCount > 200 {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.nodeInfoLargeCopyTitle
            alert.informativeText = L10n.nodeInfoLargeCopyMessage(document.lineCount)
            alert.addButton(withTitle: L10n.nodeInfoLargeCopyExport)
            alert.addButton(withTitle: L10n.nodeInfoLargeCopyCopy)
            alert.addButton(withTitle: L10n.nodeInfoLargeCopyCancel)

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                exportSelectedNodeInfo()
                return
            }
            if response != .alertSecondButtonReturn {
                return
            }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(document.text, forType: .string)
    }

    func exportSelectedNodeInfo() {
        guard let document = makeSelectedNodeInfoDocument() else { return }

        let panel = NSSavePanel()
        panel.title = L10n.nodeInfoExportTitle
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = document.suggestedFileName
        panel.allowedContentTypes = [.plainText]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try document.text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            presentOperationError(error)
        }
    }

    func showCurrentFileInFinder() {
        guard let currentFileURL = viewModel.currentFileURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([currentFileURL])
    }

    func copyCurrentFilePath() {
        guard let currentFileURL = viewModel.currentFileURL else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentFileURL.path, forType: .string)
    }

    private func bindViewModel() {
        Publishers.CombineLatest3(viewModel.$analysis, viewModel.$editableSlice, viewModel.$previewText)
            .receive(on: RunLoop.main)
            .sink { _ in }
            .store(in: &cancellables)
    }

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadLocalization()
            }
        }
    }

    private func presentOperationError(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func presentCloseConfirmation() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.closeFileConfirmationTitle
        alert.informativeText = L10n.closeFileConfirmationMessage
        alert.addButton(withTitle: L10n.closeFileConfirmationConfirm)
        alert.addButton(withTitle: L10n.closeFileConfirmationCancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func makeSelectedNodeInfoDocument() -> NodeInfoDocument? {
        guard let node = viewModel.browserSelectedNode else {
            return nil
        }

        let rows = (0..<node.detailCount).map { node.detailRow(at: $0) }
        let addressTitle = viewModel.browserAddressMode == .raw ? L10n.workspaceAddressRaw : L10n.workspaceAddressRVA

        let renderedRows = rows.map { row in
            RenderedNodeInfoRow(
                address: addressString(for: row),
                data: normalizedNodeInfoField(row.dataPreview ?? ""),
                description: normalizedNodeInfoField(row.key),
                value: normalizedNodeInfoField(row.value)
            )
        }

        let addressWidth = max(addressTitle.count, renderedRows.map { $0.address.count }.max() ?? 0)
        let dataWidth = min(47, max(L10n.workspaceDetailColumnData.count, renderedRows.map { $0.data.count }.max() ?? 0))
        let descriptionWidth = min(40, max(L10n.workspaceDetailColumnName.count, renderedRows.map { $0.description.count }.max() ?? 0))

        var lines: [String] = [node.title]
        if let subtitle = node.subtitle, subtitle.isEmpty == false {
            lines.append(subtitle)
        }
        lines.append("Rows: \(rows.count)")
        lines.append("")

        let header = formattedNodeInfoLine(
            address: addressTitle,
            data: L10n.workspaceDetailColumnData,
            description: L10n.workspaceDetailColumnName,
            value: L10n.workspaceDetailColumnValue,
            addressWidth: addressWidth,
            dataWidth: dataWidth,
            descriptionWidth: descriptionWidth
        )
        lines.append(header)
        lines.append(String(repeating: "-", count: header.count))
        lines.append(contentsOf: renderedRows.map {
            formattedNodeInfoLine(
                address: $0.address,
                data: $0.data,
                description: $0.description,
                value: $0.value,
                addressWidth: addressWidth,
                dataWidth: dataWidth,
                descriptionWidth: descriptionWidth
            )
        })

        return NodeInfoDocument(
            text: lines.joined(separator: "\n"),
            lineCount: lines.count,
            suggestedFileName: suggestedNodeInfoFileName(for: node)
        )
    }

    private func addressString(for row: BrowserDetailRow) -> String {
        let value = switch viewModel.browserAddressMode {
        case .raw:
            row.rawAddress
        case .rva:
            row.rvaAddress
        }

        guard let value else { return "" }
        return String(format: "%08llX", value)
    }

    private func formattedNodeInfoLine(
        address: String,
        data: String,
        description: String,
        value: String,
        addressWidth: Int,
        dataWidth: Int,
        descriptionWidth: Int
    ) -> String {
        "\(padded(address, width: addressWidth)) | \(padded(data, width: dataWidth)) | \(padded(description, width: descriptionWidth)) | \(value)"
    }

    private func padded(_ text: String, width: Int) -> String {
        if text.count >= width {
            return text
        }
        return text + String(repeating: " ", count: width - text.count)
    }

    private func normalizedNodeInfoField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: "    ")
    }

    private func suggestedNodeInfoFileName(for node: BrowserNode) -> String {
        let sourceName = viewModel.currentFileURL?.deletingPathExtension().lastPathComponent
            ?? viewModel.browserDocument?.sourceName
            ?? L10n.nodeInfoExportDefaultName
        let sanitizedNode = node.title.replacingOccurrences(of: "/", with: "-")
        return "\(sourceName)-\(sanitizedNode).txt"
    }

    private func stopAccessingActiveSecurityScopedURL() {
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        activeSecurityScopedURL = nil
    }
}

extension MainWindowController: MainWindowControlling {}

private struct NodeInfoDocument {
    let text: String
    let lineCount: Int
    let suggestedFileName: String
}

private struct RenderedNodeInfoRow {
    let address: String
    let data: String
    let description: String
    let value: String
}

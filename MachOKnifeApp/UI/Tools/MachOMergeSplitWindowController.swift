import AppKit
import MachOKnifeKit
import SnapKit

@MainActor
final class MachOMergeSplitWindowController: NSWindowController {
    private static let autosaveName = NSWindow.FrameAutosaveName("MachOKnifeMergeSplitWindowFrame")
    private let rootViewController: MachOMergeSplitRootViewController
    private var settingsObserver: NSObjectProtocol?

    convenience init() {
        self.init(viewController: MachOMergeSplitRootViewController())
    }

    private init(viewController: MachOMergeSplitRootViewController) {
        self.rootViewController = viewController
        let defaultSize = NSSize(width: 820, height: 700)
        let minimumSize = NSSize(width: 700, height: 520)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.mergeSplitWindowTitle
        window.contentViewController = viewController
        window.tabbingMode = .disallowed

        super.init(window: window)

        window.restoreFrame(
            autosaveName: Self.autosaveName,
            defaultSize: defaultSize,
            minSize: minimumSize
        )
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

    func reloadLocalization() {
        window?.title = L10n.mergeSplitWindowTitle
        rootViewController.reloadLocalization()
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
}

@MainActor
private final class MachOMergeSplitRootViewController: NSTabViewController {
    private let mergeController = MergeMachOViewController()
    private let splitController = SplitMachOViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar
        addChild(mergeController)
        addChild(splitController)
        reloadLocalization()
    }

    func reloadLocalization() {
        tabViewItems[safe: 0]?.label = L10n.mergeSplitMergeTab
        tabViewItems[safe: 0]?.image = NSImage(
            systemSymbolName: "square.stack.3d.up.fill",
            accessibilityDescription: L10n.mergeSplitMergeTab
        )
        tabViewItems[safe: 1]?.label = L10n.mergeSplitSplitTab
        tabViewItems[safe: 1]?.image = NSImage(
            systemSymbolName: "square.stack.3d.down.right.fill",
            accessibilityDescription: L10n.mergeSplitSplitTab
        )
        mergeController.reloadLocalization()
        splitController.reloadLocalization()
    }
}

@MainActor
private final class MergeMachOViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let service = MachOMergeSplitService()

    private let inputsLabel = makeSectionLabel("")
    private let dropView = ToolDropZoneView()
    private let inputsTableView = NSTableView()
    private let addFilesButton = NSButton(title: "", target: nil, action: nil)
    private let removeButton = NSButton(title: "", target: nil, action: nil)
    private let clearButton = NSButton(title: "", target: nil, action: nil)
    private let outputLabel = makeSectionLabel("")
    private let outputField = makeCopyablePathLabel()
    private let chooseOutputButton = NSButton(title: "", target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let startButton = NSButton(title: "", target: nil, action: nil)

    private var inputURLs: [URL] = []
    private var outputURL: URL?

    override func loadView() {
        view = AdaptiveBackgroundView(backgroundColor: .windowBackgroundColor)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reloadLocalization()
        refreshState()
    }

    func reloadLocalization() {
        inputsLabel.stringValue = L10n.mergeSplitMergeInputsLabel
        dropView.titleLabel.stringValue = L10n.mergeSplitMergeDropHint
        addFilesButton.title = L10n.mergeSplitMergeAddFiles
        removeButton.title = L10n.mergeSplitMergeRemove
        clearButton.title = L10n.mergeSplitMergeClear
        outputLabel.stringValue = L10n.mergeSplitMergeOutputLabel
        chooseOutputButton.title = L10n.mergeSplitMergeChooseOutput
        startButton.title = L10n.mergeSplitMergeStart
        outputField.stringValue = outputURL?.path ?? L10n.xcframeworkNoSelection
        if statusLabel.stringValue.isEmpty {
            statusLabel.stringValue = L10n.mergeSplitMergeIdleStatus
        }
    }

    @objc private func addFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: view.window ?? NSApp.mainWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK else { return }
            self?.appendInputURLs(panel.urls)
        }
    }

    @objc private func removeSelectedFiles(_ sender: Any?) {
        let selectedRows = inputsTableView.selectedRowIndexes.sorted(by: >)
        guard selectedRows.isEmpty == false else { return }

        for row in selectedRows where inputURLs.indices.contains(row) {
            inputURLs.remove(at: row)
        }
        refreshState()
    }

    @objc private func clearInputs(_ sender: Any?) {
        inputURLs.removeAll()
        refreshState()
    }

    @objc private func chooseOutput(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = service.suggestedMergedOutputFileName(for: inputURLs)
        panel.beginSheetModal(for: view.window ?? NSApp.mainWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.outputURL = url
            self?.refreshState()
        }
    }

    @objc private func startMerge(_ sender: Any?) {
        guard let outputURL else { return }
        do {
            try service.merge(inputURLs: inputURLs, outputURL: outputURL)
            statusLabel.stringValue = "\(L10n.mergeSplitCompletedStatus) \(outputURL.path)"
        } catch {
            statusLabel.stringValue = error.localizedDescription
            presentMergeSplitAlert(error)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        inputURLs.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard inputURLs.indices.contains(row) else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("MergeInputCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        if cell.textField == nil {
            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingMiddle
            textField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.addSubview(textField)
            textField.snp.makeConstraints { make in
                make.leading.equalToSuperview().offset(6)
                make.trailing.equalToSuperview().offset(-6)
                make.centerY.equalToSuperview()
            }
            cell.textField = textField
        }

        let url = inputURLs[row]
        cell.textField?.stringValue = url.path
        cell.toolTip = url.path
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = inputsTableView.selectedRow >= 0
    }

    private func buildUI() {
        addFilesButton.target = self
        addFilesButton.action = #selector(addFiles(_:))
        removeButton.target = self
        removeButton.action = #selector(removeSelectedFiles(_:))
        clearButton.target = self
        clearButton.action = #selector(clearInputs(_:))
        chooseOutputButton.target = self
        chooseOutputButton.action = #selector(chooseOutput(_:))
        startButton.target = self
        startButton.action = #selector(startMerge(_:))
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.maximumNumberOfLines = 2

        dropView.onFileURLsDropped = { [weak self] urls in
            self?.appendInputURLs(urls)
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MergeInputsColumn"))
        inputsTableView.addTableColumn(column)
        inputsTableView.headerView = nil
        inputsTableView.rowHeight = 22
        inputsTableView.delegate = self
        inputsTableView.dataSource = self
        inputsTableView.allowsMultipleSelection = true

        let inputsScrollView = NSScrollView()
        inputsScrollView.hasVerticalScroller = true
        inputsScrollView.drawsBackground = false
        inputsScrollView.documentView = inputsTableView

        let controls = NSStackView()
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 12

        let inputHeaderRow = NSStackView(views: [inputsLabel, NSView(), addFilesButton, removeButton, clearButton])
        inputHeaderRow.orientation = .horizontal
        inputHeaderRow.alignment = .centerY
        inputHeaderRow.spacing = 8

        let outputRow = NSStackView(views: [outputLabel, NSView(), chooseOutputButton])
        outputRow.orientation = .horizontal
        outputRow.alignment = .centerY
        outputRow.spacing = 8

        controls.addArrangedSubview(inputHeaderRow)
        controls.addArrangedSubview(dropView)
        controls.addArrangedSubview(inputsScrollView)
        controls.addArrangedSubview(outputRow)
        controls.addArrangedSubview(outputField)
        controls.addArrangedSubview(startButton)
        controls.addArrangedSubview(statusLabel)
        view.addSubview(controls)

        controls.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(20)
        }
        dropView.snp.makeConstraints { make in
            make.width.equalTo(controls)
            make.height.equalTo(96)
        }
        inputsScrollView.snp.makeConstraints { make in
            make.width.equalTo(controls)
            make.height.equalTo(260)
        }
    }

    private func appendInputURLs(_ urls: [URL]) {
        var existing = Set(inputURLs.map { $0.standardizedFileURL.path })
        let newURLs = urls.filter {
            let path = $0.standardizedFileURL.path
            guard existing.contains(path) == false else { return false }
            existing.insert(path)
            return true
        }
        inputURLs.append(contentsOf: newURLs)
        refreshState()
    }

    private func refreshState() {
        inputsTableView.reloadData()
        outputField.stringValue = outputURL?.path ?? L10n.xcframeworkNoSelection
        removeButton.isEnabled = inputsTableView.selectedRow >= 0
        clearButton.isEnabled = inputURLs.isEmpty == false
        startButton.isEnabled = inputURLs.count >= 2 && outputURL != nil
        if inputURLs.isEmpty {
            statusLabel.stringValue = L10n.mergeSplitMergeIdleStatus
        }
    }

    private func presentMergeSplitAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.mergeSplitErrorTitle
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.beginSheetModal(for: view.window ?? NSWindow())
    }
}

@MainActor
private final class SplitMachOViewController: NSViewController {
    private let service = MachOMergeSplitService()

    private let inputLabel = makeSectionLabel("")
    private let chooseInputButton = NSButton(title: "", target: nil, action: nil)
    private let clearInputButton = NSButton(title: "", target: nil, action: nil)
    private let inputPathLabel = makeCopyablePathLabel()
    private let dropView = ToolDropZoneView()
    private let architecturesLabel = makeSectionLabel("")
    private let architecturesValueLabel = makeCopyablePathLabel()
    private let outputDirectoryLabel = makeSectionLabel("")
    private let outputDirectoryField = makeCopyablePathLabel()
    private let chooseDirectoryButton = NSButton(title: "", target: nil, action: nil)
    private let clearOutputDirectoryButton = NSButton(title: "", target: nil, action: nil)
    private let startButton = NSButton(title: "", target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    private var inputURL: URL?
    private var outputDirectoryURL: URL?
    private var architectures: [String] = []

    override func loadView() {
        view = AdaptiveBackgroundView(backgroundColor: .windowBackgroundColor)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reloadLocalization()
        refreshState()
    }

    func reloadLocalization() {
        inputLabel.stringValue = L10n.mergeSplitSplitInputLabel
        chooseInputButton.title = L10n.mergeSplitSplitChooseInput
        clearInputButton.title = L10n.mergeSplitMergeClear
        architecturesLabel.stringValue = L10n.mergeSplitSplitArchitecturesLabel
        outputDirectoryLabel.stringValue = L10n.mergeSplitSplitOutputDirectoryLabel
        chooseDirectoryButton.title = L10n.mergeSplitSplitChooseDirectory
        clearOutputDirectoryButton.title = L10n.mergeSplitMergeClear
        startButton.title = L10n.mergeSplitSplitStart
        dropView.titleLabel.stringValue = L10n.mergeSplitSplitDropHint
        inputPathLabel.stringValue = inputURL?.path ?? L10n.xcframeworkNoSelection
        outputDirectoryField.stringValue = outputDirectoryURL?.path ?? L10n.xcframeworkNoSelection
        architecturesValueLabel.stringValue = architectures.isEmpty ? L10n.xcframeworkNoSelection : architectures.joined(separator: ", ")
        if statusLabel.stringValue.isEmpty {
            statusLabel.stringValue = L10n.mergeSplitSplitIdleStatus
        }
    }

    @objc private func chooseInput(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: view.window ?? NSApp.mainWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadInput(url)
        }
    }

    @objc private func clearInput(_ sender: Any?) {
        inputURL = nil
        architectures = []
        refreshState()
    }

    @objc private func chooseDirectory(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: view.window ?? NSApp.mainWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.outputDirectoryURL = url
            self?.refreshState()
        }
    }

    @objc private func clearOutputDirectory(_ sender: Any?) {
        outputDirectoryURL = nil
        refreshState()
    }

    @objc private func startSplit(_ sender: Any?) {
        guard let inputURL, let outputDirectoryURL else { return }
        do {
            let outputs = try service.split(
                inputURL: inputURL,
                architectures: architectures,
                outputDirectoryURL: outputDirectoryURL
            )
            statusLabel.stringValue = "\(L10n.mergeSplitCompletedStatus) \(outputs.map(\.lastPathComponent).joined(separator: ", "))"
        } catch {
            statusLabel.stringValue = error.localizedDescription
            presentMergeSplitAlert(error)
        }
    }

    private func buildUI() {
        chooseInputButton.target = self
        chooseInputButton.action = #selector(chooseInput(_:))
        clearInputButton.target = self
        clearInputButton.action = #selector(clearInput(_:))
        chooseDirectoryButton.target = self
        chooseDirectoryButton.action = #selector(chooseDirectory(_:))
        clearOutputDirectoryButton.target = self
        clearOutputDirectoryButton.action = #selector(clearOutputDirectory(_:))
        startButton.target = self
        startButton.action = #selector(startSplit(_:))
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.maximumNumberOfLines = 2

        dropView.onFileURLDropped = { [weak self] url in
            self?.loadInput(url)
        }

        let controls = NSStackView()
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 12

        let inputRow = NSStackView(views: [inputLabel, NSView(), chooseInputButton, clearInputButton])
        inputRow.orientation = .horizontal
        inputRow.alignment = .centerY
        inputRow.spacing = 8

        let outputRow = NSStackView(views: [outputDirectoryLabel, NSView(), chooseDirectoryButton, clearOutputDirectoryButton])
        outputRow.orientation = .horizontal
        outputRow.alignment = .centerY
        outputRow.spacing = 8

        controls.addArrangedSubview(inputRow)
        controls.addArrangedSubview(inputPathLabel)
        controls.addArrangedSubview(dropView)
        controls.addArrangedSubview(architecturesLabel)
        controls.addArrangedSubview(architecturesValueLabel)
        controls.addArrangedSubview(outputRow)
        controls.addArrangedSubview(outputDirectoryField)
        controls.addArrangedSubview(startButton)
        controls.addArrangedSubview(statusLabel)
        view.addSubview(controls)

        controls.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(20)
        }
        dropView.snp.makeConstraints { make in
            make.width.equalTo(controls)
            make.height.equalTo(120)
        }
    }

    private func loadInput(_ url: URL) {
        inputURL = url
        do {
            architectures = try service.availableArchitectures(for: url)
            refreshState()
        } catch {
            architectures = []
            refreshState()
            presentMergeSplitAlert(error)
        }
    }

    private func refreshState() {
        inputPathLabel.stringValue = inputURL?.path ?? L10n.xcframeworkNoSelection
        outputDirectoryField.stringValue = outputDirectoryURL?.path ?? L10n.xcframeworkNoSelection
        architecturesValueLabel.stringValue = architectures.isEmpty ? L10n.xcframeworkNoSelection : architectures.joined(separator: ", ")
        clearInputButton.isEnabled = inputURL != nil
        clearOutputDirectoryButton.isEnabled = outputDirectoryURL != nil
        startButton.isEnabled = inputURL != nil && outputDirectoryURL != nil && architectures.isEmpty == false
        if inputURL == nil {
            statusLabel.stringValue = L10n.mergeSplitSplitIdleStatus
        }
    }

    private func presentMergeSplitAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.mergeSplitErrorTitle
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.beginSheetModal(for: view.window ?? NSWindow())
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

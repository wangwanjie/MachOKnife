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

    /// 用主工作区当前打开的文件预填“拆分”和“移除架构”的输入（合并需要多个输入，不做预填）。
    /// 用户已在工具里手动选择了其他文件、或操作正在进行时保持不变。
    func prefill(withWorkspaceDocument url: URL) {
        _ = window
        rootViewController.prefill(withWorkspaceDocument: url)
    }

    /// “移除架构”表单的状态（供测试读取）。
    var removeArchitecturesViewModel: RemoveArchitecturesViewModel {
        _ = window
        return rootViewController.removeArchitecturesViewModel
    }

    /// “拆分”表单当前的输入文件（供测试读取）。
    var splitInputURL: URL? {
        _ = window
        return rootViewController.splitInputURL
    }

    /// 当前选中的标签页标题（供测试读取）。
    var selectedTabLabel: String? {
        _ = window
        return rootViewController.selectedTabLabel
    }

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue, so refresh synchronously instead of hopping through a Task.
            MainActor.assumeIsolated {
                self?.reloadLocalization()
            }
        }
    }
}

@MainActor
private final class MachOMergeSplitRootViewController: NSTabViewController {
    private let mergeController = MergeMachOViewController()
    private let splitController = SplitMachOViewController()
    private let removeController = RemoveArchitecturesViewController()
    private var splitHandOff = WorkspaceToolHandOff()
    private var removeHandOff = WorkspaceToolHandOff()

    var removeArchitecturesViewModel: RemoveArchitecturesViewModel {
        removeController.viewModel
    }

    var splitInputURL: URL? {
        splitController.inputURL
    }

    var selectedTabLabel: String? {
        tabViewItems[safe: selectedTabViewItemIndex]?.label
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar
        addChild(mergeController)
        addChild(splitController)
        addChild(removeController)
        reloadLocalization()
    }

    func prefill(withWorkspaceDocument url: URL) {
        _ = view
        // 预填时不弹出错误提示：工作区文件可能是单架构文件，此时只在表单中显示检测结果。
        if splitController.isRunning == false,
           let target = splitHandOff.inputToPrefill(workspaceDocumentURL: url, currentInputURL: splitController.inputURL) {
            splitController.loadInput(target, presentingErrors: false)
        }
        if removeController.viewModel.isRunning == false,
           let target = removeHandOff.inputToPrefill(
               workspaceDocumentURL: url,
               currentInputURL: removeController.viewModel.inputURL
           ) {
            removeController.loadInput(target, presentingErrors: false)
        }
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
        tabViewItems[safe: 2]?.label = L10n.mergeSplitRemoveTab
        tabViewItems[safe: 2]?.image = NSImage(
            systemSymbolName: "scissors",
            accessibilityDescription: L10n.mergeSplitRemoveTab
        )
        mergeController.reloadLocalization()
        splitController.reloadLocalization()
        removeController.reloadLocalization()
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
    private var status: MergeSplitStatus = .idle
    private var activeOperationID: UUID?

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
        renderStatus()
    }

    private func setStatus(_ newStatus: MergeSplitStatus) {
        status = newStatus
        renderStatus()
    }

    private func renderStatus() {
        statusLabel.stringValue = status.text(idle: L10n.mergeSplitMergeIdleStatus)
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
        inputsDidChange()
    }

    @objc private func clearInputs(_ sender: Any?) {
        inputURLs.removeAll()
        inputsDidChange()
    }

    @objc private func chooseOutput(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = service.suggestedMergedOutputFileName(for: inputURLs)
        panel.beginSheetModal(for: view.window ?? NSApp.mainWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.outputURL = url
            self?.inputsDidChange()
        }
    }

    @objc private func startMerge(_ sender: Any?) {
        guard let outputURL, activeOperationID == nil else { return }
        let inputURLs = inputURLs
        let operationID = UUID()
        activeOperationID = operationID
        setStatus(.running)
        refreshState()

        // Merging copies whole binaries, so it runs off the main thread.
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result<Void, Error> {
                try MachOMergeSplitService().merge(inputURLs: inputURLs, outputURL: outputURL)
            }
            // 直接 await 主线程隔离的方法，避免在嵌套的并发闭包里引用被捕获的 weak self（Swift 6 下会报错）。
            await self?.finishMerge(result, operationID: operationID, outputURL: outputURL)
        }
    }

    private func finishMerge(_ result: Result<Void, Error>, operationID: UUID, outputURL: URL) {
        guard activeOperationID == operationID else { return }
        activeOperationID = nil
        switch result {
        case .success:
            setStatus(.completed(outputURL.path))
        case let .failure(error):
            setStatus(.failed(error))
            presentMergeSplitAlert(error)
        }
        refreshState()
    }

    /// Inputs or the output changed, so any previous "completed" or error status no longer applies.
    private func inputsDidChange() {
        if activeOperationID == nil {
            status = .idle
        }
        refreshState()
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
        removeButton.isEnabled = activeOperationID == nil && inputsTableView.selectedRow >= 0
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
            guard self?.activeOperationID == nil else { return }
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
        inputsDidChange()
    }

    private func refreshState() {
        inputsTableView.reloadData()
        outputField.stringValue = outputURL?.path ?? L10n.xcframeworkNoSelection
        let running = activeOperationID != nil
        removeButton.isEnabled = !running && inputsTableView.selectedRow >= 0
        clearButton.isEnabled = !running && inputURLs.isEmpty == false
        addFilesButton.isEnabled = !running
        chooseOutputButton.isEnabled = !running
        startButton.isEnabled = !running && inputURLs.count >= 2 && outputURL != nil
        renderStatus()
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

    private(set) var inputURL: URL?
    private var outputDirectoryURL: URL?
    private var architectures: [String] = []
    private var status: MergeSplitStatus = .idle
    private var activeOperationID: UUID?

    override func loadView() {
        view = AdaptiveBackgroundView(backgroundColor: .windowBackgroundColor)
    }

    var isRunning: Bool {
        activeOperationID != nil
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
        renderStatus()
    }

    private func setStatus(_ newStatus: MergeSplitStatus) {
        status = newStatus
        renderStatus()
    }

    private func renderStatus() {
        statusLabel.stringValue = status.text(idle: L10n.mergeSplitSplitIdleStatus)
    }

    /// Input or output changed, so any previous "completed" or error status no longer applies.
    private func inputsDidChange() {
        if activeOperationID == nil {
            status = .idle
        }
        refreshState()
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
        inputsDidChange()
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
            self?.inputsDidChange()
        }
    }

    @objc private func clearOutputDirectory(_ sender: Any?) {
        outputDirectoryURL = nil
        inputsDidChange()
    }

    @objc private func startSplit(_ sender: Any?) {
        guard let inputURL, let outputDirectoryURL, activeOperationID == nil else { return }
        let architectures = architectures
        let operationID = UUID()
        activeOperationID = operationID
        setStatus(.running)
        refreshState()

        // Splitting writes one file per architecture, so it runs off the main thread.
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result<[URL], Error> {
                try MachOMergeSplitService().split(
                    inputURL: inputURL,
                    architectures: architectures,
                    outputDirectoryURL: outputDirectoryURL
                )
            }
            // 直接 await 主线程隔离的方法，避免在嵌套的并发闭包里引用被捕获的 weak self（Swift 6 下会报错）。
            await self?.finishSplit(result, operationID: operationID)
        }
    }

    private func finishSplit(_ result: Result<[URL], Error>, operationID: UUID) {
        guard activeOperationID == operationID else { return }
        activeOperationID = nil
        switch result {
        case let .success(outputs):
            setStatus(.completed(outputs.map(\.lastPathComponent).joined(separator: ", ")))
        case let .failure(error):
            setStatus(.failed(error))
            presentMergeSplitAlert(error)
        }
        refreshState()
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
            guard self?.activeOperationID == nil else { return }
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

    /// 载入输入文件并检测架构；`presentingErrors` 为 false 时（例如从工作区预填）检测失败不弹窗。
    func loadInput(_ url: URL, presentingErrors: Bool = true) {
        inputURL = url
        do {
            architectures = try service.availableArchitectures(for: url)
            inputsDidChange()
        } catch {
            architectures = []
            inputsDidChange()
            if presentingErrors {
                presentMergeSplitAlert(error)
            }
        }
    }

    private func refreshState() {
        inputPathLabel.stringValue = inputURL?.path ?? L10n.xcframeworkNoSelection
        outputDirectoryField.stringValue = outputDirectoryURL?.path ?? L10n.xcframeworkNoSelection
        architecturesValueLabel.stringValue = architectures.isEmpty ? L10n.xcframeworkNoSelection : architectures.joined(separator: ", ")
        let running = activeOperationID != nil
        chooseInputButton.isEnabled = !running
        chooseDirectoryButton.isEnabled = !running
        clearInputButton.isEnabled = !running && inputURL != nil
        clearOutputDirectoryButton.isEnabled = !running && outputDirectoryURL != nil
        startButton.isEnabled = !running && inputURL != nil && outputDirectoryURL != nil && architectures.isEmpty == false
        renderStatus()
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
private final class RemoveArchitecturesViewController: NSViewController {
    let viewModel = RemoveArchitecturesViewModel()

    private let inputLabel = makeSectionLabel("")
    private let chooseInputButton = NSButton(title: "", target: nil, action: nil)
    private let clearInputButton = NSButton(title: "", target: nil, action: nil)
    private let inputPathLabel = makeCopyablePathLabel()
    private let dropView = ToolDropZoneView()
    private let architecturesLabel = makeSectionLabel("")
    private let architecturesStackView = NSStackView()
    private let architecturesHintLabel = NSTextField(wrappingLabelWithString: "")
    private let outputLabel = makeSectionLabel("")
    private let outputField = makeCopyablePathLabel()
    private let chooseOutputButton = NSButton(title: "", target: nil, action: nil)
    private let startButton = NSButton(title: "", target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    /// 当前展示的架构复选框对应的架构列表，变化时才重建复选框。
    private var renderedArchitectures: [String] = []

    override func loadView() {
        view = AdaptiveBackgroundView(backgroundColor: .windowBackgroundColor)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        viewModel.onChange = { [weak self] in
            self?.refreshState()
        }
        reloadLocalization()
    }

    func reloadLocalization() {
        inputLabel.stringValue = L10n.mergeSplitRemoveInputLabel
        chooseInputButton.title = L10n.mergeSplitSplitChooseInput
        clearInputButton.title = L10n.mergeSplitMergeClear
        dropView.titleLabel.stringValue = L10n.mergeSplitRemoveDropHint
        architecturesLabel.stringValue = L10n.mergeSplitRemoveArchitecturesLabel
        outputLabel.stringValue = L10n.mergeSplitMergeOutputLabel
        chooseOutputButton.title = L10n.mergeSplitMergeChooseOutput
        startButton.title = L10n.mergeSplitRemoveStart
        refreshState()
    }

    /// 载入输入文件；`presentingErrors` 为 false 时（例如从工作区预填）读取失败不弹窗。
    func loadInput(_ url: URL, presentingErrors: Bool = true) {
        do {
            try viewModel.loadInput(url)
        } catch {
            if presentingErrors {
                presentMergeSplitAlert(error)
            }
        }
    }

    @objc private func chooseInput(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: view.window ?? NSApp.mainWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            self?.loadInput(url)
        }
    }

    @objc private func clearInput(_ sender: Any?) {
        viewModel.clearInput()
    }

    @objc private func chooseOutput(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = viewModel.suggestedOutputFileName
        panel.directoryURL = viewModel.inputURL?.deletingLastPathComponent()
        panel.beginSheetModal(for: view.window ?? NSApp.mainWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            self?.viewModel.setOutputURL(url)
        }
    }

    @objc private func architectureCheckboxChanged(_ sender: NSButton) {
        guard let architecture = sender.identifier?.rawValue else {
            return
        }
        viewModel.setArchitecture(architecture, removed: sender.state == .on)
    }

    @objc private func startRemoval(_ sender: Any?) {
        guard let task = viewModel.start() else {
            return
        }
        // 与合并/拆分一致：操作失败时除了状态文字外再弹出提示框。
        Task { [weak self] in
            await task.value
            guard let self, case let .failed(error) = self.viewModel.status else {
                return
            }
            self.presentMergeSplitAlert(error)
        }
    }

    private func buildUI() {
        chooseInputButton.target = self
        chooseInputButton.action = #selector(chooseInput(_:))
        clearInputButton.target = self
        clearInputButton.action = #selector(clearInput(_:))
        chooseOutputButton.target = self
        chooseOutputButton.action = #selector(chooseOutput(_:))
        startButton.target = self
        startButton.action = #selector(startRemoval(_:))
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.maximumNumberOfLines = 2
        architecturesHintLabel.textColor = .secondaryLabelColor
        architecturesHintLabel.maximumNumberOfLines = 2

        architecturesStackView.orientation = .horizontal
        architecturesStackView.alignment = .centerY
        architecturesStackView.spacing = 16

        dropView.onFileURLDropped = { [weak self] url in
            guard self?.viewModel.isRunning == false else {
                return
            }
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

        let outputRow = NSStackView(views: [outputLabel, NSView(), chooseOutputButton])
        outputRow.orientation = .horizontal
        outputRow.alignment = .centerY
        outputRow.spacing = 8

        controls.addArrangedSubview(inputRow)
        controls.addArrangedSubview(inputPathLabel)
        controls.addArrangedSubview(dropView)
        controls.addArrangedSubview(architecturesLabel)
        controls.addArrangedSubview(architecturesStackView)
        controls.addArrangedSubview(architecturesHintLabel)
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
            make.height.equalTo(120)
        }
        inputRow.snp.makeConstraints { make in
            make.width.equalTo(controls)
        }
        outputRow.snp.makeConstraints { make in
            make.width.equalTo(controls)
        }
    }

    private func refreshState() {
        inputPathLabel.stringValue = viewModel.inputURL?.path ?? L10n.xcframeworkNoSelection
        outputField.stringValue = viewModel.outputURL?.path ?? L10n.xcframeworkNoSelection
        rebuildArchitectureCheckboxesIfNeeded()

        let running = viewModel.isRunning
        for case let checkbox as NSButton in architecturesStackView.arrangedSubviews {
            let architecture = checkbox.identifier?.rawValue ?? ""
            checkbox.state = viewModel.architecturesToRemove.contains(architecture) ? .on : .off
            checkbox.isEnabled = !running && viewModel.hasRemovableArchitectures
        }
        architecturesHintLabel.stringValue = architecturesHint()
        chooseInputButton.isEnabled = !running
        clearInputButton.isEnabled = !running && viewModel.inputURL != nil
        chooseOutputButton.isEnabled = !running && viewModel.inputURL != nil
        startButton.isEnabled = viewModel.canStart
        statusLabel.stringValue = statusText()
    }

    private func rebuildArchitectureCheckboxesIfNeeded() {
        guard renderedArchitectures != viewModel.availableArchitectures else {
            return
        }
        renderedArchitectures = viewModel.availableArchitectures
        for arrangedSubview in architecturesStackView.arrangedSubviews {
            architecturesStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        // 架构名称本身不需要本地化，复选框的 identifier 保存架构名，便于回调时识别。
        for architecture in renderedArchitectures {
            let checkbox = NSButton(checkboxWithTitle: architecture, target: self, action: #selector(architectureCheckboxChanged(_:)))
            checkbox.identifier = NSUserInterfaceItemIdentifier(architecture)
            architecturesStackView.addArrangedSubview(checkbox)
        }
    }

    /// 架构区下方的提示：没有输入、只有一个架构、全部勾选时给出对应说明。
    private func architecturesHint() -> String {
        if viewModel.inputURL == nil {
            return L10n.mergeSplitRemoveArchitecturesHint
        }
        if viewModel.availableArchitectures.isEmpty {
            return L10n.mergeSplitRemoveNoArchitectures
        }
        if viewModel.hasRemovableArchitectures == false {
            return L10n.mergeSplitRemoveSingleArchitecture
        }
        if viewModel.removesEveryArchitecture {
            return L10n.mergeSplitRemoveKeepOne
        }
        return L10n.mergeSplitRemoveArchitecturesHint
    }

    private func statusText() -> String {
        switch viewModel.status {
        case .idle:
            return L10n.mergeSplitRemoveIdleStatus
        case .running:
            return L10n.mergeSplitRunningStatus
        case let .completed(outputURL):
            return "\(L10n.mergeSplitCompletedStatus) \(outputURL.path)"
        case let .failed(error):
            return error.localizedDescription
        }
    }

    private func presentMergeSplitAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.mergeSplitErrorTitle
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        guard let window = view.window, window.isVisible else {
            // 窗口不可见（例如尚未显示）时错误已体现在表单中，不再弹出无处附着的提示框。
            return
        }
        alert.beginSheetModal(for: window)
    }
}

/// Status shown under the merge and split forms. Rendered from state (not stored as text)
/// so a language change re-localizes it.
private enum MergeSplitStatus {
    case idle
    case running
    case completed(String)
    case failed(Error)

    @MainActor
    func text(idle idleText: String) -> String {
        switch self {
        case .idle:
            return idleText
        case .running:
            return L10n.mergeSplitRunningStatus
        case let .completed(detail):
            return "\(L10n.mergeSplitCompletedStatus) \(detail)"
        case let .failed(error):
            return error.localizedDescription
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

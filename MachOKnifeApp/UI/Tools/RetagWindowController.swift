import AppKit
import CoreMachO
import MachOKnifeKit
import MachO
import RetagEngine
import SnapKit

@MainActor
final class RetagWindowController: NSWindowController {
    private static let autosaveName = NSWindow.FrameAutosaveName("MachOKnifeRetagWindowFrame")
    private let retagViewController: RetagViewController
    private var settingsObserver: NSObjectProtocol?

    convenience init() {
        self.init(viewController: RetagViewController())
    }

    private init(viewController: RetagViewController) {
        self.retagViewController = viewController
        let defaultSize = NSSize(width: 760, height: 640)
        let minimumSize = NSSize(width: 680, height: 520)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.retagWindowTitle
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
        window?.title = L10n.retagWindowTitle
        retagViewController.reloadLocalization()
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
private final class RetagViewController: NSViewController {
    private let analysisService = DocumentAnalysisService()
    private let archiveInspector = ArchiveInspector()
    private let retagEngine = RetagEngine()
    private let supportedPlatforms: [MachOPlatform] = [
        .macOS,
        .iOS,
        .iOSSimulator,
        .macCatalyst,
        .tvOS,
        .tvOSSimulator,
        .watchOS,
        .watchOSSimulator,
        .visionOS,
        .visionOSSimulator,
        .driverKit,
        .bridgeOS,
        .firmware,
        .sepOS,
    ]

    private let inputTitleLabel = NSTextField(labelWithString: "")
    private let chooseInputButton = NSButton(title: "", target: nil, action: nil)
    private let clearInputButton = NSButton(title: "", target: nil, action: nil)
    private let inputPathLabel = makeCopyablePathLabel()
    private let inputDropView = ToolDropZoneView()
    private let infoTitleLabel = NSTextField(labelWithString: "")
    private let infoScrollView = NSTextView.scrollableTextView()
    private var infoTextView: NSTextView {
        infoScrollView.documentView as! NSTextView
    }
    private let architectureLabel = makeSectionLabel("")
    private let architecturePopUpButton = NSPopUpButton()
    private let targetLabel = makeSectionLabel("")
    private let targetPopUpButton = NSPopUpButton()
    private let minimumOSLabel = makeSectionLabel("")
    private let minimumOSTextField = NSTextField(string: "")
    private let sdkLabel = makeSectionLabel("")
    private let sdkTextField = NSTextField(string: "")
    private let outputDirectoryLabel = makeSectionLabel("")
    private let outputDirectoryField = makeCopyablePathLabel()
    private let chooseOutputDirectoryButton = NSButton(title: "", target: nil, action: nil)
    private let clearOutputDirectoryButton = NSButton(title: "", target: nil, action: nil)
    private let outputNameLabel = makeSectionLabel("")
    private let outputNameField = NSTextField(string: "")
    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let startButton = NSButton(title: "", target: nil, action: nil)
    private let cancelButton = NSButton(title: "", target: nil, action: nil)

    private var inputURL: URL?
    private var outputDirectoryURL: URL?
    private var activeInputSecurityScopedURL: URL?
    private var activeOutputSecurityScopedURL: URL?
    private var analysis: DocumentAnalysis?
    private var archiveInspection: ArchiveInspection?
    private var architectureRow: NSStackView?
    private var retagTask: Task<Void, Never>?
    /// Identifies the retag whose result is still wanted. Cancelling clears it, so a result that
    /// arrives afterwards is discarded (and its staged output removed) instead of being published.
    private var activeRetagID: UUID?
    private var lastDiffEntries: [DiffEntry] = []
    private var status: RetagStatus = .idle

    private enum RetagStatus {
        case idle
        case running
        case completed(URL)
        case cancelled
        case failed(Error)
    }

    deinit {
        Self.stopAccessingSecurityScope(activeInputSecurityScopedURL)
        Self.stopAccessingSecurityScope(activeOutputSecurityScopedURL)
    }

    override func loadView() {
        view = AdaptiveBackgroundView(backgroundColor: .windowBackgroundColor)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reloadLocalization()
        applyIdleState()
    }

    @objc private func chooseInputFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = L10n.retagInputTitle
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: view.window ?? NSApp.mainWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadInput(url)
        }
    }

    @objc private func chooseOutputDirectory(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputDirectoryURL ?? inputURL?.deletingLastPathComponent()
        panel.beginSheetModal(for: view.window ?? NSApp.mainWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.adoptOutputDirectoryURL(url)
            self?.refreshOutputFields()
            self?.setRunning(self?.activeRetagID != nil)
        }
    }

    @objc private func clearInput(_ sender: Any?) {
        Self.stopAccessingSecurityScope(activeInputSecurityScopedURL)
        activeInputSecurityScopedURL = nil
        inputURL = nil
        analysis = nil
        archiveInspection = nil
        architecturePopUpButton.removeAllItems()
        architectureRow?.isHidden = true
        applyIdleState()
    }

    @objc private func clearOutputDirectory(_ sender: Any?) {
        Self.stopAccessingSecurityScope(activeOutputSecurityScopedURL)
        activeOutputSecurityScopedURL = nil
        outputDirectoryURL = nil
        refreshOutputFields()
        setRunning(activeRetagID != nil)
    }

    @objc private func archiveArchitectureChanged(_ sender: Any?) {
        refreshDetectedSummary()
    }

    @objc private func startRetag(_ sender: Any?) {
        guard let inputURL, activeRetagID == nil else { return }

        do {
            guard let outputDirectoryURL else {
                throw RetagUIError.outputDirectoryMissing
            }
            let platform = supportedPlatforms[targetPopUpButton.indexOfSelectedItem]
            let minimumOS = try parseVersion(minimumOSTextField.stringValue)
            let sdk = try parseVersion(sdkTextField.stringValue)
            let outputName = outputNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !outputName.isEmpty else {
                throw RetagUIError.outputNameMissing
            }
            guard outputName.contains("/") == false, outputName != ".", outputName != ".." else {
                throw RetagUIError.invalidOutputName(outputName)
            }

            let outputURL = outputDirectoryURL.appendingPathComponent(outputName)
            // The engine writes synchronously and cannot be interrupted, so it writes to a private
            // staging file. The staged file is only moved into place if the retag was not cancelled.
            let stagingURL = outputDirectoryURL.appendingPathComponent(".\(outputName).machoknife-retag-\(UUID().uuidString)")
            let architecture = selectedArchiveArchitecture()
            let engine = retagEngine
            let retagID = UUID()

            activeRetagID = retagID
            lastDiffEntries = []
            refreshDetectedSummary()
            setRunning(true)
            setStatus(.running)

            retagTask = Task.detached(priority: .userInitiated) { [weak self] in
                let outcome: Result<[DiffEntry], Error>
                do {
                    try Task.checkCancellation()
                    let result = try engine.retagPlatform(
                        inputURL: inputURL,
                        outputURL: stagingURL,
                        platform: platform,
                        minimumOS: minimumOS,
                        sdk: sdk,
                        architecture: architecture
                    )
                    outcome = .success(result.diff.entries)
                } catch {
                    outcome = .failure(error)
                }

                await MainActor.run {
                    guard let self else {
                        try? FileManager.default.removeItem(at: stagingURL)
                        return
                    }
                    self.finishRetag(
                        retagID: retagID,
                        outcome: outcome,
                        stagingURL: stagingURL,
                        outputURL: outputURL
                    )
                }
            }
        } catch {
            showErrorAlert(error)
        }
    }

    private func finishRetag(retagID: UUID, outcome: Result<[DiffEntry], Error>, stagingURL: URL, outputURL: URL) {
        guard activeRetagID == retagID else {
            // Cancelled (or superseded) while the engine was running: discard the staged output.
            try? FileManager.default.removeItem(at: stagingURL)
            return
        }

        activeRetagID = nil
        retagTask = nil
        setRunning(false)

        switch outcome {
        case let .success(entries):
            do {
                try Self.moveStagedOutput(stagingURL, to: outputURL)
                setStatus(.completed(outputURL))
                lastDiffEntries = entries
                refreshDetectedSummary()
            } catch {
                try? FileManager.default.removeItem(at: stagingURL)
                showErrorAlert(error)
            }
        case let .failure(error):
            try? FileManager.default.removeItem(at: stagingURL)
            if error is CancellationError {
                setStatus(.cancelled)
            } else {
                showErrorAlert(error)
            }
        }
    }

    private static func moveStagedOutput(_ stagingURL: URL, to outputURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            _ = try fileManager.replaceItemAt(outputURL, withItemAt: stagingURL)
        } else {
            try fileManager.moveItem(at: stagingURL, to: outputURL)
        }
    }

    @objc private func cancelRetag(_ sender: Any?) {
        activeRetagID = nil
        retagTask?.cancel()
        retagTask = nil
        setRunning(false)
        setStatus(.cancelled)
    }

    private func setStatus(_ newStatus: RetagStatus) {
        status = newStatus
        renderStatus()
    }

    private func renderStatus() {
        switch status {
        case .idle:
            statusLabel.stringValue = L10n.retagIdleStatus
        case .running:
            statusLabel.stringValue = L10n.retagRunningStatus
        case let .completed(url):
            statusLabel.stringValue = L10n.retagCompletedStatus(path: url.path)
        case .cancelled:
            statusLabel.stringValue = L10n.retagCancelledStatus
        case let .failed(error):
            statusLabel.stringValue = error.localizedDescription
        }
    }

    private func buildUI() {
        inputTitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        chooseInputButton.target = self
        chooseInputButton.action = #selector(chooseInputFile(_:))
        clearInputButton.target = self
        clearInputButton.action = #selector(clearInput(_:))

        inputDropView.onFileURLDropped = { [weak self] url in
            self?.loadInput(url)
        }

        let inputActionRow = NSStackView(views: [inputTitleLabel, NSView(), chooseInputButton, clearInputButton])
        inputActionRow.orientation = .horizontal
        inputActionRow.alignment = .centerY
        inputActionRow.spacing = 8

        let inputStack = NSStackView(views: [inputActionRow, inputPathLabel])
        inputStack.orientation = .vertical
        inputStack.alignment = .leading
        inputStack.spacing = 8

        infoTitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        infoTextView.isEditable = false
        infoTextView.isSelectable = true
        infoTextView.drawsBackground = false
        infoTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        infoTextView.textColor = .textColor

        infoScrollView.drawsBackground = false
        infoScrollView.hasVerticalScroller = true
        infoScrollView.autohidesScrollers = true

        architecturePopUpButton.target = self
        architecturePopUpButton.action = #selector(archiveArchitectureChanged(_:))

        supportedPlatforms.forEach { targetPopUpButton.addItem(withTitle: platformName($0)) }

        chooseOutputDirectoryButton.target = self
        chooseOutputDirectoryButton.action = #selector(chooseOutputDirectory(_:))
        clearOutputDirectoryButton.target = self
        clearOutputDirectoryButton.action = #selector(clearOutputDirectory(_:))

        startButton.target = self
        startButton.action = #selector(startRetag(_:))
        startButton.bezelStyle = .rounded

        cancelButton.target = self
        cancelButton.action = #selector(cancelRetag(_:))
        cancelButton.bezelStyle = .rounded

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.isIndeterminate = true
        progressIndicator.isDisplayedWhenStopped = false

        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byTruncatingMiddle

        let architectureRow = makeRow(label: architectureLabel, control: architecturePopUpButton)
        architectureRow.isHidden = true
        self.architectureRow = architectureRow
        let targetRow = makeRow(label: targetLabel, control: targetPopUpButton)
        let minimumOSRow = makeRow(label: minimumOSLabel, control: minimumOSTextField)
        let sdkRow = makeRow(label: sdkLabel, control: sdkTextField)
        let outputNameRow = makeRow(label: outputNameLabel, control: outputNameField)

        let outputDirectoryControls = NSStackView(views: [outputDirectoryField, chooseOutputDirectoryButton, clearOutputDirectoryButton])
        outputDirectoryControls.orientation = .horizontal
        outputDirectoryControls.alignment = .centerY
        outputDirectoryControls.spacing = 8
        let outputDirectoryRow = makeRow(label: outputDirectoryLabel, control: outputDirectoryControls)

        let buttonRow = NSStackView(views: [startButton, cancelButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let statusRow = NSStackView(views: [progressIndicator, statusLabel, NSView()])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8

        let stack = NSStackView(views: [
            inputStack,
            inputDropView,
            infoTitleLabel,
            infoScrollView,
            architectureRow,
            targetRow,
            minimumOSRow,
            sdkRow,
            outputDirectoryRow,
            outputNameRow,
            statusRow,
            buttonRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14

        view.addSubview(stack)

        inputDropView.snp.makeConstraints { make in
            make.height.equalTo(96)
        }
        infoScrollView.snp.makeConstraints { make in
            make.height.equalTo(180)
        }
        outputDirectoryField.snp.makeConstraints { make in
            make.width.greaterThanOrEqualTo(380)
        }
        [chooseInputButton, clearInputButton, chooseOutputDirectoryButton, clearOutputDirectoryButton].forEach {
            $0.snp.makeConstraints { make in
                make.width.equalTo(96)
            }
        }
        architecturePopUpButton.snp.makeConstraints { make in
            make.width.greaterThanOrEqualTo(220)
        }
        targetPopUpButton.snp.makeConstraints { make in
            make.width.greaterThanOrEqualTo(220)
        }
        minimumOSTextField.snp.makeConstraints { make in
            make.width.equalTo(180)
        }
        sdkTextField.snp.makeConstraints { make in
            make.width.equalTo(180)
        }
        outputNameField.snp.makeConstraints { make in
            make.width.greaterThanOrEqualTo(260)
        }
        stack.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(20)
            make.trailing.bottom.lessThanOrEqualToSuperview().inset(20)
        }
    }

    func reloadLocalization() {
        view.window?.title = L10n.retagWindowTitle
        inputTitleLabel.stringValue = L10n.retagInputTitle
        chooseInputButton.title = L10n.retagInputChoose
        clearInputButton.title = L10n.mergeSplitMergeClear
        inputDropView.titleLabel.stringValue = L10n.retagInputDropHint
        infoTitleLabel.stringValue = L10n.retagInfoTitle
        architectureLabel.stringValue = L10n.retagArchitectureLabel
        targetLabel.stringValue = L10n.retagTargetLabel
        minimumOSLabel.stringValue = L10n.retagMinimumOSLabel
        sdkLabel.stringValue = L10n.retagSDKLabel
        outputDirectoryLabel.stringValue = L10n.retagOutputDirectoryLabel
        outputNameLabel.stringValue = L10n.retagOutputNameLabel
        chooseOutputDirectoryButton.title = L10n.retagChooseDirectory
        clearOutputDirectoryButton.title = L10n.mergeSplitMergeClear
        startButton.title = L10n.retagStart
        cancelButton.title = L10n.retagCancel
        if inputURL == nil {
            inputPathLabel.stringValue = L10n.retagNoInputInfo
        }
        refreshOutputFields()
        refreshDetectedSummary()
        renderStatus()
    }

    private func loadInput(_ url: URL) {
        let previousInputURL = activeInputSecurityScopedURL
        let reusesExistingScope = previousInputURL?.standardizedFileURL == url.standardizedFileURL
        let didAccessInputScope = reusesExistingScope ? false : url.startAccessingSecurityScopedResource()

        do {
            if let archiveInspection = try archiveInspector.inspect(url: url) {
                adoptInputURL(url, reusesExistingScope: reusesExistingScope, didAccessSecurityScope: didAccessInputScope)
                loadArchiveInput(url, inspection: archiveInspection)
                return
            }

            let analysis = try analysisService.analyze(url: url)
            adoptInputURL(url, reusesExistingScope: reusesExistingScope, didAccessSecurityScope: didAccessInputScope)
            self.inputURL = url
            self.analysis = analysis
            archiveInspection = nil
            lastDiffEntries = []

            inputPathLabel.stringValue = url.path
            clearInputButton.isEnabled = true
            outputNameField.stringValue = suggestedOutputName(for: url)
            configureArchitectureSelection(using: nil)

            let firstSlice = analysis.slices.first
            if let platform = firstSlice?.platform, let index = supportedPlatforms.firstIndex(of: platform) {
                targetPopUpButton.selectItem(at: index)
            } else {
                targetPopUpButton.selectItem(at: 0)
            }

            minimumOSTextField.stringValue = firstSlice?.minimumOS?.description ?? "0.0.0"
            sdkTextField.stringValue = firstSlice?.sdkVersion?.description ?? firstSlice?.minimumOS?.description ?? "0.0.0"
            refreshDetectedSummary()
            setStatus(.idle)
            refreshOutputFields()
            setRunning(false)
        } catch {
            if didAccessInputScope {
                url.stopAccessingSecurityScopedResource()
            }
            showErrorAlert(error)
        }
    }

    private func applyIdleState() {
        inputURL = nil
        analysis = nil
        archiveInspection = nil
        targetPopUpButton.selectItem(at: 0)
        configureArchitectureSelection(using: nil)
        lastDiffEntries = []
        inputPathLabel.stringValue = L10n.retagNoInputInfo
        outputDirectoryField.stringValue = outputDirectoryURL?.path ?? L10n.retagNoOutputDirectory
        outputNameField.stringValue = L10n.retagOutputDefaultName
        infoTextView.string = L10n.retagNoInputInfo + "\n\n" + L10n.retagUnsupportedPlaceholder
        setStatus(.idle)
        clearInputButton.isEnabled = false
        clearOutputDirectoryButton.isEnabled = outputDirectoryURL != nil
        setRunning(false)
    }

    private func refreshOutputFields() {
        outputDirectoryField.stringValue = outputDirectoryURL?.path ?? L10n.retagNoOutputDirectory
        clearOutputDirectoryButton.isEnabled = outputDirectoryURL != nil
        if outputNameField.stringValue.isEmpty, let inputURL {
            outputNameField.stringValue = suggestedOutputName(for: inputURL)
        }
    }

    private func setRunning(_ running: Bool) {
        chooseInputButton.isEnabled = !running
        clearInputButton.isEnabled = !running && inputURL != nil
        chooseOutputDirectoryButton.isEnabled = !running
        clearOutputDirectoryButton.isEnabled = !running && outputDirectoryURL != nil
        startButton.isEnabled = !running && inputURL != nil && outputDirectoryURL != nil
        architecturePopUpButton.isEnabled = !running
        cancelButton.isEnabled = running
        architecturePopUpButton.isEnabled = !running && (archiveInspection?.architectures.count ?? 0) > 1
        targetPopUpButton.isEnabled = !running
        minimumOSTextField.isEnabled = !running
        sdkTextField.isEnabled = !running
        outputNameField.isEnabled = !running
        if running {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
    }

    private func loadArchiveInput(_ url: URL, inspection: ArchiveInspection) {
        inputURL = url
        analysis = nil
        archiveInspection = inspection
        lastDiffEntries = []

        inputPathLabel.stringValue = url.path
        clearInputButton.isEnabled = true
        outputNameField.stringValue = suggestedOutputName(for: url)
        configureArchitectureSelection(using: inspection)
        refreshDetectedSummary()
        setStatus(.idle)
        refreshOutputFields()
        setRunning(false)
    }

    private func adoptInputURL(_ url: URL, reusesExistingScope: Bool, didAccessSecurityScope: Bool) {
        guard reusesExistingScope == false else { return }
        Self.stopAccessingSecurityScope(activeInputSecurityScopedURL)
        activeInputSecurityScopedURL = didAccessSecurityScope ? url : nil
    }

    private func adoptOutputDirectoryURL(_ url: URL) {
        let reusesExistingScope = activeOutputSecurityScopedURL?.standardizedFileURL == url.standardizedFileURL
        let didAccessSecurityScope = reusesExistingScope ? false : url.startAccessingSecurityScopedResource()

        if reusesExistingScope == false {
            Self.stopAccessingSecurityScope(activeOutputSecurityScopedURL)
            activeOutputSecurityScopedURL = didAccessSecurityScope ? url : nil
        }

        outputDirectoryURL = url
    }

    nonisolated private static func stopAccessingSecurityScope(_ url: URL?) {
        url?.stopAccessingSecurityScopedResource()
    }

    private func configureArchitectureSelection(using inspection: ArchiveInspection?) {
        architecturePopUpButton.removeAllItems()

        guard let inspection else {
            architectureRow?.isHidden = true
            return
        }

        inspection.architectures.forEach { architecturePopUpButton.addItem(withTitle: $0) }
        if architecturePopUpButton.numberOfItems > 0 {
            architecturePopUpButton.selectItem(at: 0)
        }
        architecturePopUpButton.isEnabled = inspection.architectures.count > 1
        architectureRow?.isHidden = false
    }

    private func selectedArchiveArchitecture() -> String? {
        guard archiveInspection != nil, architecturePopUpButton.numberOfItems > 0 else {
            return nil
        }
        return architecturePopUpButton.titleOfSelectedItem
    }

    private func refreshDetectedSummary() {
        guard let inputURL else {
            infoTextView.string = L10n.retagNoInputInfo + "\n\n" + L10n.retagUnsupportedPlaceholder
            return
        }

        var summary: String
        if let archiveInspection {
            summary = makeArchiveSummary(
                url: inputURL,
                inspection: archiveInspection,
                selectedArchitecture: selectedArchiveArchitecture()
            )
        } else if let analysis {
            summary = makeAnalysisSummary(url: inputURL, analysis: analysis)
        } else {
            summary = L10n.retagNoInputInfo + "\n\n" + L10n.retagUnsupportedPlaceholder
        }

        if let diffSummary = makeDiffSummary(lastDiffEntries) {
            summary += "\n\n" + diffSummary
        }
        infoTextView.string = summary
    }

    private func makeAnalysisSummary(url: URL, analysis: DocumentAnalysis) -> String {
        let notAvailable = L10n.retagSummaryNotAvailable
        var lines = [
            "\(L10n.retagSummaryFile): \(url.path)",
            "\(L10n.retagSummaryContainer): \(analysis.containerKind)",
            "\(L10n.retagSummarySlices): \(analysis.slices.count)",
        ]

        for (index, slice) in analysis.slices.enumerated() {
            let cpuDescription = cpuTypeDescription(slice.header.cpuType)
            let fileTypeDescription = fileTypeDescription(slice.header.fileType)
            lines.append("")
            lines.append("\(L10n.viewerSliceTitle(index)) (\(cpuDescription))")
            lines.append("  \(L10n.retagSummaryCPU): \(cpuDescription) (\(String(format: "0x%08X", UInt32(bitPattern: slice.header.cpuType))) / \(slice.header.cpuType))")
            lines.append("  \(L10n.retagSummaryFileType): \(fileTypeDescription) (\(String(format: "0x%08X", slice.header.fileType)) / \(slice.header.fileType))")
            lines.append("  \(L10n.retagSummaryPlatform): \(slice.platform.map(platformName) ?? notAvailable)")
            lines.append("  \(L10n.retagMinimumOSLabel): \(slice.minimumOS?.description ?? notAvailable)")
            lines.append("  \(L10n.retagSDKLabel): \(slice.sdkVersion?.description ?? notAvailable)")
            lines.append("  \(L10n.retagSummaryInstallName): \(slice.installName ?? L10n.retagSummaryNone)")
        }

        lines.append("")
        lines.append(L10n.retagUnsupportedPlaceholder)
        return lines.joined(separator: "\n")
    }

    private func makeArchiveSummary(
        url: URL,
        inspection: ArchiveInspection,
        selectedArchitecture: String?
    ) -> String {
        let containerName = inspection.kind == .fatArchive ? L10n.retagSummaryFatStaticArchive : L10n.retagSummaryStaticArchive
        var lines = [
            "\(L10n.retagSummaryFile): \(url.path)",
            "\(L10n.retagSummaryContainer): \(containerName)",
            "\(L10n.retagSummaryArchitectures): \(inspection.architectures.joined(separator: ", "))",
        ]

        if let selectedArchitecture {
            lines.append("\(L10n.retagSummarySelectedArchitecture): \(selectedArchitecture)")
        }

        lines.append("")
        lines.append(L10n.retagSummaryArchiveNote)
        lines.append("")
        lines.append(L10n.retagUnsupportedPlaceholder)
        return lines.joined(separator: "\n")
    }

    private func makeDiffSummary(_ entries: [DiffEntry]) -> String? {
        guard !entries.isEmpty else { return nil }
        let summary = entries.map { entry in
            let before = entry.originalValue ?? L10n.retagSummaryNone
            let after = entry.updatedValue ?? L10n.retagSummaryNone
            return "[\(entry.sliceOffset)] \(String(describing: entry.kind)): \(before) -> \(after)"
        }.joined(separator: "\n")
        return "\(L10n.retagSummaryDiff)\n\(summary)"
    }

    private func showErrorAlert(_ error: Error) {
        setStatus(.failed(error))
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.retagErrorTitle
        alert.informativeText = error.localizedDescription
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func parseVersion(_ value: String) throws -> MachOVersion {
        guard let version = RetagVersionParser.parse(value) else {
            throw RetagUIError.invalidVersion(value)
        }
        return version
    }

    private func suggestedOutputName(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        return "\(stem)-retagged\(suffix)"
    }

    private func platformName(_ platform: MachOPlatform) -> String {
        switch platform {
        case .macOS: return "macOS"
        case .iOS: return "iOS"
        case .tvOS: return "tvOS"
        case .watchOS: return "watchOS"
        case .bridgeOS: return "bridgeOS"
        case .macCatalyst: return "Mac Catalyst"
        case .iOSSimulator: return "iOS Simulator"
        case .tvOSSimulator: return "tvOS Simulator"
        case .watchOSSimulator: return "watchOS Simulator"
        case .driverKit: return "DriverKit"
        case .visionOS: return "visionOS"
        case .visionOSSimulator: return "visionOS Simulator"
        case .firmware: return "Firmware"
        case .sepOS: return "sepOS"
        case let .unknown(value): return "Unknown(\(value))"
        }
    }

    private func cpuTypeDescription(_ value: Int32) -> String {
        switch value {
        case CPU_TYPE_ARM64:
            "arm64"
        case CPU_TYPE_X86_64:
            "x86_64"
        case CPU_TYPE_ARM:
            "arm"
        case CPU_TYPE_X86:
            "x86"
        case CPU_TYPE_POWERPC:
            "powerpc"
        case CPU_TYPE_POWERPC64:
            "powerpc64"
        default:
            "unknown"
        }
    }

    private func fileTypeDescription(_ value: UInt32) -> String {
        switch value {
        case UInt32(MH_OBJECT):
            "Relocatable Object"
        case UInt32(MH_EXECUTE):
            "Executable"
        case UInt32(MH_FVMLIB):
            "Fixed VM Library"
        case UInt32(MH_CORE):
            "Core"
        case UInt32(MH_PRELOAD):
            "Preloaded Executable"
        case UInt32(MH_DYLIB):
            "Dynamic Library"
        case UInt32(MH_DYLINKER):
            "Dynamic Linker"
        case UInt32(MH_BUNDLE):
            "Bundle"
        case UInt32(MH_DYLIB_STUB):
            "Shared Library Stub"
        case UInt32(MH_DSYM):
            "dSYM Companion"
        case UInt32(MH_KEXT_BUNDLE):
            "Kext Bundle"
        case UInt32(MH_FILESET):
            "Fileset"
        default:
            "Unknown"
        }
    }
}

/// Strict parser for Mach-O packed versions: 1–3 dot-separated decimal components,
/// major ≤ 65535 and minor/patch ≤ 255 (the `xxxx.yy.zz` nibble layout of LC_BUILD_VERSION).
enum RetagVersionParser {
    static func parse(_ value: String) -> MachOVersion? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else {
            return nil
        }

        var numbers: [Int] = []
        for part in parts {
            guard part.isEmpty == false,
                  part.count <= 5,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part) else {
                return nil
            }
            numbers.append(number)
        }

        let major = numbers[0]
        let minor = numbers.count > 1 ? numbers[1] : 0
        let patch = numbers.count > 2 ? numbers[2] : 0
        guard major <= 0xFFFF, minor <= 0xFF, patch <= 0xFF else {
            return nil
        }
        return MachOVersion(major: major, minor: minor, patch: patch)
    }
}

private enum RetagUIError: LocalizedError {
    case outputDirectoryMissing
    case outputNameMissing
    case invalidOutputName(String)
    case invalidVersion(String)

    var errorDescription: String? {
        switch self {
        case .outputDirectoryMissing:
            return L10n.retagErrorOutputDirectoryMissing
        case .outputNameMissing:
            return L10n.retagErrorOutputNameMissing
        case let .invalidOutputName(value):
            return L10n.retagErrorInvalidOutputName(value)
        case let .invalidVersion(value):
            return L10n.retagErrorInvalidVersion(value)
        }
    }
}

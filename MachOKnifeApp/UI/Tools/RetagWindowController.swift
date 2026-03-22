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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.retagWindowTitle
        window.contentViewController = viewController
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 680, height: 520)

        super.init(window: window)

        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)
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
            Task { @MainActor [weak self] in
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
    private let inputPathLabel = NSTextField(wrappingLabelWithString: "")
    private let inputDropView = RetagDropZoneView()
    private let infoTitleLabel = NSTextField(labelWithString: "")
    private let infoTextView = NSTextView()
    private let architectureLabel = makeSectionLabel("")
    private let architecturePopUpButton = NSPopUpButton()
    private let targetLabel = makeSectionLabel("")
    private let targetPopUpButton = NSPopUpButton()
    private let minimumOSLabel = makeSectionLabel("")
    private let minimumOSTextField = NSTextField(string: "")
    private let sdkLabel = makeSectionLabel("")
    private let sdkTextField = NSTextField(string: "")
    private let outputDirectoryLabel = makeSectionLabel("")
    private let outputDirectoryField = NSTextField(wrappingLabelWithString: "")
    private let chooseOutputDirectoryButton = NSButton(title: "", target: nil, action: nil)
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
        }
    }

    @objc private func archiveArchitectureChanged(_ sender: Any?) {
        refreshDetectedSummary()
    }

    @objc private func startRetag(_ sender: Any?) {
        guard let inputURL else { return }

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

            let outputURL = outputDirectoryURL.appendingPathComponent(outputName)
            retagTask?.cancel()
            retagTask = Task { [weak self] in
                guard let self else { return }
                await MainActor.run {
                    self.setRunning(true)
                    self.statusLabel.stringValue = L10n.retagRunningStatus
                }

                do {
                    try Task.checkCancellation()
                    // TODO: RetagEngine writes synchronously today, so mid-write cancellation is best-effort only.
                    let result = try retagEngine.retagPlatform(
                        inputURL: inputURL,
                        outputURL: outputURL,
                        platform: platform,
                        minimumOS: minimumOS,
                        sdk: sdk,
                        architecture: selectedArchiveArchitecture()
                    )
                    try Task.checkCancellation()

                    await MainActor.run {
                        self.retagTask = nil
                        self.setRunning(false)
                        self.statusLabel.stringValue = L10n.retagCompletedStatus(path: result.outputURL.path)
                        self.appendDiffSummary(result.diff.entries)
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self.retagTask = nil
                        self.setRunning(false)
                        self.statusLabel.stringValue = L10n.retagCancelledStatus
                    }
                } catch {
                    await MainActor.run {
                        self.retagTask = nil
                        self.setRunning(false)
                        self.showErrorAlert(error)
                    }
                }
            }
        } catch {
            showErrorAlert(error)
        }
    }

    @objc private func cancelRetag(_ sender: Any?) {
        retagTask?.cancel()
        retagTask = nil
        setRunning(false)
        statusLabel.stringValue = L10n.retagCancelledStatus
    }

    private func buildUI() {
        inputTitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        inputTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        chooseInputButton.target = self
        chooseInputButton.action = #selector(chooseInputFile(_:))

        inputPathLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        inputPathLabel.textColor = .secondaryLabelColor

        inputDropView.onFileURLDropped = { [weak self] url in
            self?.loadInput(url)
        }
        inputDropView.translatesAutoresizingMaskIntoConstraints = false

        let inputStack = NSStackView(views: [inputTitleLabel, chooseInputButton, inputPathLabel])
        inputStack.orientation = .vertical
        inputStack.alignment = .leading
        inputStack.spacing = 8
        inputStack.translatesAutoresizingMaskIntoConstraints = false

        infoTitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        infoTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        infoTextView.isEditable = false
        infoTextView.isSelectable = true
        infoTextView.drawsBackground = false
        infoTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        let infoScrollView = NSScrollView()
        infoScrollView.translatesAutoresizingMaskIntoConstraints = false
        infoScrollView.drawsBackground = false
        infoScrollView.hasVerticalScroller = true
        infoScrollView.documentView = infoTextView

        architecturePopUpButton.target = self
        architecturePopUpButton.action = #selector(archiveArchitectureChanged(_:))

        supportedPlatforms.forEach { targetPopUpButton.addItem(withTitle: platformName($0)) }

        chooseOutputDirectoryButton.target = self
        chooseOutputDirectoryButton.action = #selector(chooseOutputDirectory(_:))

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
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 0

        let architectureRow = makeRow(label: architectureLabel, control: architecturePopUpButton)
        architectureRow.isHidden = true
        self.architectureRow = architectureRow
        let targetRow = makeRow(label: targetLabel, control: targetPopUpButton)
        let minimumOSRow = makeRow(label: minimumOSLabel, control: minimumOSTextField)
        let sdkRow = makeRow(label: sdkLabel, control: sdkTextField)
        let outputNameRow = makeRow(label: outputNameLabel, control: outputNameField)

        let outputDirectoryControls = NSStackView(views: [outputDirectoryField, chooseOutputDirectoryButton])
        outputDirectoryControls.orientation = .horizontal
        outputDirectoryControls.alignment = .centerY
        outputDirectoryControls.spacing = 8
        let outputDirectoryRow = makeRow(label: outputDirectoryLabel, control: outputDirectoryControls)

        let buttonRow = NSStackView(views: [startButton, cancelButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let statusRow = NSStackView(views: [progressIndicator, statusLabel, NSView()])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8
        statusRow.translatesAutoresizingMaskIntoConstraints = false

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
        stack.translatesAutoresizingMaskIntoConstraints = false

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
        inputDropView.titleLabel.stringValue = L10n.retagInputDropHint
        infoTitleLabel.stringValue = L10n.retagInfoTitle
        architectureLabel.stringValue = L10n.retagArchitectureLabel
        targetLabel.stringValue = L10n.retagTargetLabel
        minimumOSLabel.stringValue = L10n.retagMinimumOSLabel
        sdkLabel.stringValue = L10n.retagSDKLabel
        outputDirectoryLabel.stringValue = L10n.retagOutputDirectoryLabel
        outputNameLabel.stringValue = L10n.retagOutputNameLabel
        chooseOutputDirectoryButton.title = L10n.retagChooseDirectory
        startButton.title = L10n.retagStart
        cancelButton.title = L10n.retagCancel
        refreshOutputFields()
        if inputURL != nil {
            refreshDetectedSummary()
        } else if infoTextView.string.isEmpty {
            infoTextView.string = L10n.retagNoInputInfo + "\n\n" + L10n.retagUnsupportedPlaceholder
        }
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
            if outputDirectoryURL == nil {
                adoptOutputDirectoryURL(url.deletingLastPathComponent())
            }

            inputPathLabel.stringValue = url.path
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
            statusLabel.stringValue = L10n.retagIdleStatus
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
        inputPathLabel.stringValue = L10n.retagNoInputInfo
        outputDirectoryField.stringValue = L10n.retagNoInputInfo
        outputNameField.stringValue = L10n.retagOutputDefaultName
        infoTextView.string = L10n.retagNoInputInfo + "\n\n" + L10n.retagUnsupportedPlaceholder
        statusLabel.stringValue = L10n.retagIdleStatus
        setRunning(false)
    }

    private func refreshOutputFields() {
        outputDirectoryField.stringValue = outputDirectoryURL?.path ?? L10n.retagNoInputInfo
        if outputNameField.stringValue.isEmpty, let inputURL {
            outputNameField.stringValue = suggestedOutputName(for: inputURL)
        }
    }

    private func setRunning(_ running: Bool) {
        chooseInputButton.isEnabled = !running
        chooseOutputDirectoryButton.isEnabled = !running
        startButton.isEnabled = !running && inputURL != nil && outputDirectoryURL != nil
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
        if outputDirectoryURL == nil {
            adoptOutputDirectoryURL(url.deletingLastPathComponent())
        }

        inputPathLabel.stringValue = url.path
        outputNameField.stringValue = suggestedOutputName(for: url)
        configureArchitectureSelection(using: inspection)
        refreshDetectedSummary()
        statusLabel.stringValue = L10n.retagIdleStatus
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

        if let archiveInspection {
            infoTextView.string = makeArchiveSummary(
                url: inputURL,
                inspection: archiveInspection,
                selectedArchitecture: selectedArchiveArchitecture()
            )
            return
        }

        if let analysis {
            infoTextView.string = makeAnalysisSummary(url: inputURL, analysis: analysis)
            return
        }

        infoTextView.string = L10n.retagNoInputInfo + "\n\n" + L10n.retagUnsupportedPlaceholder
    }

    private func makeAnalysisSummary(url: URL, analysis: DocumentAnalysis) -> String {
        var lines = [
            "File: \(url.path)",
            "Container: \(analysis.containerKind)",
            "Slices: \(analysis.slices.count)",
        ]

        for (index, slice) in analysis.slices.enumerated() {
            let cpuDescription = cpuTypeDescription(slice.header.cpuType)
            let fileTypeDescription = fileTypeDescription(slice.header.fileType)
            lines.append("")
            lines.append("Slice \(index) (\(cpuDescription))")
            lines.append("  CPU: \(cpuDescription) (\(String(format: "0x%08X", UInt32(bitPattern: slice.header.cpuType))) / \(slice.header.cpuType))")
            lines.append("  File Type: \(fileTypeDescription) (\(String(format: "0x%08X", slice.header.fileType)) / \(slice.header.fileType))")
            lines.append("  Platform: \(slice.platform.map(platformName) ?? "n/a")")
            lines.append("  Minimum OS: \(slice.minimumOS?.description ?? "n/a")")
            lines.append("  SDK: \(slice.sdkVersion?.description ?? "n/a")")
            lines.append("  Install Name: \(slice.installName ?? "(none)")")
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
        var lines = [
            "File: \(url.path)",
            "Container: \(inspection.kind == .fatArchive ? "Fat Static Archive" : "Static Archive")",
            "Architectures: \(inspection.architectures.joined(separator: ", "))",
        ]

        if let selectedArchitecture {
            lines.append("Selected Architecture: \(selectedArchitecture)")
        }

        lines.append("")
        lines.append("Retag rewrites object members inside the selected static-archive architecture only.")
        lines.append("")
        lines.append(L10n.retagUnsupportedPlaceholder)
        return lines.joined(separator: "\n")
    }

    private func appendDiffSummary(_ entries: [DiffEntry]) {
        guard !entries.isEmpty else { return }
        let summary = entries.map { entry in
            let before = entry.originalValue ?? "(none)"
            let after = entry.updatedValue ?? "(none)"
            return "[\(entry.sliceOffset)] \(String(describing: entry.kind)): \(before) -> \(after)"
        }.joined(separator: "\n")
        infoTextView.string += "\n\nDiff\n\(summary)"
    }

    private func showErrorAlert(_ error: Error) {
        statusLabel.stringValue = error.localizedDescription
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
        let components = value
            .split(separator: ".")
            .map(String.init)
            .compactMap(Int.init)

        switch components.count {
        case 2:
            return MachOVersion(major: components[0], minor: components[1], patch: 0)
        case 3:
            return MachOVersion(major: components[0], minor: components[1], patch: components[2])
        default:
            throw RetagUIError.invalidVersion(value)
        }
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

private enum RetagUIError: LocalizedError {
    case outputDirectoryMissing
    case outputNameMissing
    case invalidVersion(String)

    var errorDescription: String? {
        switch self {
        case .outputDirectoryMissing:
            return "Choose an output directory."
        case .outputNameMissing:
            return "Enter an output file name."
        case let .invalidVersion(value):
            return "Invalid version: \(value)"
        }
    }
}

private final class RetagDropZoneView: AdaptiveBackgroundView {
    let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let iconView = NSImageView()
    var onFileURLDropped: ((URL) -> Void)?

    override init(backgroundColor: NSColor = .controlBackgroundColor) {
        super.init(backgroundColor: backgroundColor)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1.5
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.82).cgColor

        iconView.image = NSImage(systemSymbolName: "square.and.arrow.down.on.square.dashed", accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        iconView.contentTintColor = .secondaryLabelColor

        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 0
        titleLabel.textColor = .secondaryLabelColor
        addSubview(iconView)
        addSubview(titleLabel)
        iconView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(titleLabel.snp.top).offset(-8)
        }
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().inset(12)
            make.trailing.lessThanOrEqualToSuperview().inset(12)
        }

        registerForDraggedTypes([.fileURL])
        updateBorderAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        updateBorderAppearance()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard
            let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]),
            let url = items.first as? URL
        else {
            return false
        }

        updateBorderAppearance()
        onFileURLDropped?(url)
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorderAppearance()
    }

    private func updateBorderAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.borderColor = (isDark ? NSColor.separatorColor : NSColor.systemGray.withAlphaComponent(0.7)).cgColor
    }
}

import AppKit
import SnapKit

@MainActor
final class XCFrameworkBuildWindowController: NSWindowController {
    private static let autosaveName = NSWindow.FrameAutosaveName("MachOKnifeXCFrameworkBuildWindowFrame")
    private let buildViewController: XCFrameworkBuildViewController
    private var settingsObserver: NSObjectProtocol?

    convenience init() {
        self.init(viewController: XCFrameworkBuildViewController())
    }

    private init(viewController: XCFrameworkBuildViewController) {
        self.buildViewController = viewController
        let defaultSize = NSSize(width: 820, height: 720)
        let minimumSize = NSSize(width: 720, height: 620)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.xcframeworkWindowTitle
        window.contentViewController = viewController
        super.init(window: window)
        self.window?.tabbingMode = .disallowed
        self.window?.title = L10n.xcframeworkWindowTitle
        if let window = self.window {
            window.restoreFrame(
                autosaveName: Self.autosaveName,
                defaultSize: defaultSize,
                minSize: minimumSize
            )
        }
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
        window?.title = L10n.xcframeworkWindowTitle
        (window?.contentViewController as? XCFrameworkBuildViewController)?.reloadLocalization()
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
private final class XCFrameworkBuildViewController: NSViewController {
    private let buildService = XCFrameworkBuildService()

    private let helpTitleLabel = NSTextField(labelWithString: "")
    private let helpTextLabel = makeHintLabel("")
    private let sourceLibraryLabel = makeSectionLabel("")
    private let sourceLibraryField = DropReceivingPathLabel()
    private let sourceLibraryButton = NSButton(title: "", target: nil, action: nil)
    private let sourceLibraryClearButton = NSButton(title: "", target: nil, action: nil)
    private let deviceLibraryLabel = makeSectionLabel("")
    private let deviceLibraryField = DropReceivingPathLabel()
    private let deviceLibraryButton = NSButton(title: "", target: nil, action: nil)
    private let deviceLibraryClearButton = NSButton(title: "", target: nil, action: nil)
    private let simulatorLibraryLabel = makeSectionLabel("")
    private let simulatorLibraryField = DropReceivingPathLabel()
    private let simulatorLibraryButton = NSButton(title: "", target: nil, action: nil)
    private let simulatorLibraryClearButton = NSButton(title: "", target: nil, action: nil)
    private let macCatalystLibraryLabel = makeSectionLabel("")
    private let macCatalystLibraryField = DropReceivingPathLabel()
    private let macCatalystLibraryButton = NSButton(title: "", target: nil, action: nil)
    private let macCatalystLibraryClearButton = NSButton(title: "", target: nil, action: nil)
    private let headersLabel = makeSectionLabel("")
    private let headersField = DropReceivingPathLabel()
    private let headersButton = NSButton(title: "", target: nil, action: nil)
    private let headersClearButton = NSButton(title: "", target: nil, action: nil)
    private let outputDirectoryLabel = makeSectionLabel("")
    private let outputDirectoryField = DropReceivingPathLabel()
    private let outputDirectoryButton = NSButton(title: "", target: nil, action: nil)
    private let outputDirectoryClearButton = NSButton(title: "", target: nil, action: nil)
    private let outputLibraryNameLabel = makeSectionLabel("")
    private let outputLibraryNameField = NSTextField(string: "libSDK.a")
    private let xcframeworkNameLabel = makeSectionLabel("")
    private let xcframeworkNameField = NSTextField(string: "SDK.xcframework")
    private let moduleNameLabel = makeSectionLabel("")
    private let moduleNameField = NSTextField(string: "")
    private let umbrellaHeaderLabel = makeSectionLabel("")
    private let umbrellaHeaderField = NSTextField(string: "")
    private let minVersionLabel = makeSectionLabel("")
    private let minVersionField = NSTextField(string: "13.1")
    private let sdkVersionLabel = makeSectionLabel("")
    private let sdkVersionField = NSTextField(string: "17.5")
    private let logTitleLabel = NSTextField(labelWithString: "")
    private let logTextView = NSTextView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let startButton = NSButton(title: "", target: nil, action: nil)
    private let cancelButton = NSButton(title: "", target: nil, action: nil)

    private var sourceLibraryURL: URL?
    private var deviceLibraryURL: URL?
    private var simulatorLibraryURL: URL?
    private var macCatalystLibraryURL: URL?
    private var headersDirectoryURL: URL?
    private var outputDirectoryURL: URL?

    override func loadView() {
        view = AdaptiveBackgroundView(backgroundColor: .windowBackgroundColor)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reloadLocalization()
        applyIdleState()
    }

    func reloadLocalization() {
        helpTitleLabel.stringValue = L10n.xcframeworkHelpTitle
        helpTextLabel.stringValue = L10n.xcframeworkHelpText
        sourceLibraryLabel.stringValue = L10n.xcframeworkSourceLibraryLabel
        deviceLibraryLabel.stringValue = L10n.xcframeworkDeviceLibraryLabel
        simulatorLibraryLabel.stringValue = L10n.xcframeworkSimulatorLibraryLabel
        macCatalystLibraryLabel.stringValue = L10n.xcframeworkMacCatalystLibraryLabel
        headersLabel.stringValue = L10n.xcframeworkHeadersLabel
        outputDirectoryLabel.stringValue = L10n.xcframeworkOutputDirectoryLabel
        outputLibraryNameLabel.stringValue = L10n.xcframeworkOutputLibraryNameLabel
        xcframeworkNameLabel.stringValue = L10n.xcframeworkOutputNameLabel
        moduleNameLabel.stringValue = L10n.xcframeworkModuleNameLabel
        umbrellaHeaderLabel.stringValue = L10n.xcframeworkUmbrellaHeaderLabel
        minVersionLabel.stringValue = L10n.xcframeworkMinVersionLabel
        sdkVersionLabel.stringValue = L10n.xcframeworkSDKVersionLabel
        logTitleLabel.stringValue = L10n.xcframeworkLogTitle
        sourceLibraryButton.title = L10n.xcframeworkChooseFile
        sourceLibraryClearButton.title = L10n.mergeSplitMergeClear
        deviceLibraryButton.title = L10n.xcframeworkChooseFile
        deviceLibraryClearButton.title = L10n.mergeSplitMergeClear
        simulatorLibraryButton.title = L10n.xcframeworkChooseFile
        simulatorLibraryClearButton.title = L10n.mergeSplitMergeClear
        macCatalystLibraryButton.title = L10n.xcframeworkChooseFile
        macCatalystLibraryClearButton.title = L10n.mergeSplitMergeClear
        headersButton.title = L10n.xcframeworkChooseDirectory
        headersClearButton.title = L10n.mergeSplitMergeClear
        outputDirectoryButton.title = L10n.xcframeworkChooseDirectory
        outputDirectoryClearButton.title = L10n.mergeSplitMergeClear
        startButton.title = L10n.xcframeworkStart
        cancelButton.title = L10n.xcframeworkCancel
        if statusLabel.stringValue.isEmpty {
            statusLabel.stringValue = L10n.xcframeworkIdleStatus
        }
    }

    @objc private func chooseSourceLibrary(_ sender: Any?) {
        chooseFile { [weak self] url in
            self?.applySourceLibrary(url)
        }
    }

    @objc private func chooseDeviceLibrary(_ sender: Any?) {
        chooseFile { [weak self] url in
            self?.applyDeviceLibrary(url)
        }
    }

    @objc private func chooseSimulatorLibrary(_ sender: Any?) {
        chooseFile { [weak self] url in
            self?.applySimulatorLibrary(url)
        }
    }

    @objc private func chooseMacCatalystLibrary(_ sender: Any?) {
        chooseFile { [weak self] url in
            self?.applyMacCatalystLibrary(url)
        }
    }

    @objc private func chooseHeadersDirectory(_ sender: Any?) {
        chooseDirectory { [weak self] url in
            self?.applyHeadersDirectory(url)
        }
    }

    @objc private func chooseOutputDirectory(_ sender: Any?) {
        chooseDirectory { [weak self] url in
            self?.applyOutputDirectory(url)
        }
    }

    private func applySourceLibrary(_ url: URL) {
        sourceLibraryURL = url
        sourceLibraryField.stringValue = url.path
        sourceLibraryField.showsPlaceholderText = false
        sourceLibraryClearButton.isEnabled = true
        if deviceLibraryURL == nil {
            deviceLibraryField.stringValue = L10n.xcframeworkUseSourceLibraryHint
            deviceLibraryField.showsPlaceholderText = true
            deviceLibraryClearButton.isEnabled = false
        }
        if simulatorLibraryURL == nil {
            simulatorLibraryField.stringValue = L10n.xcframeworkUseSourceLibraryHint
            simulatorLibraryField.showsPlaceholderText = true
            simulatorLibraryClearButton.isEnabled = false
        }
        if macCatalystLibraryURL == nil {
            macCatalystLibraryField.stringValue = L10n.xcframeworkMacCatalystOptionalHint
            macCatalystLibraryField.showsPlaceholderText = true
            macCatalystLibraryClearButton.isEnabled = false
        }
        updateStartAvailability()
    }

    private func applyDeviceLibrary(_ url: URL) {
        deviceLibraryURL = url
        deviceLibraryField.stringValue = url.path
        deviceLibraryField.showsPlaceholderText = false
        deviceLibraryClearButton.isEnabled = true
        updateStartAvailability()
    }

    private func applySimulatorLibrary(_ url: URL) {
        simulatorLibraryURL = url
        simulatorLibraryField.stringValue = url.path
        simulatorLibraryField.showsPlaceholderText = false
        simulatorLibraryClearButton.isEnabled = true
        updateStartAvailability()
    }

    private func applyMacCatalystLibrary(_ url: URL) {
        macCatalystLibraryURL = url
        macCatalystLibraryField.stringValue = url.path
        macCatalystLibraryField.showsPlaceholderText = false
        macCatalystLibraryClearButton.isEnabled = true
    }

    private func applyHeadersDirectory(_ url: URL) {
        headersDirectoryURL = url
        headersField.stringValue = url.path
        headersField.showsPlaceholderText = false
        headersClearButton.isEnabled = true
        updateStartAvailability()
    }

    private func applyOutputDirectory(_ url: URL) {
        outputDirectoryURL = url
        outputDirectoryField.stringValue = url.path
        outputDirectoryField.showsPlaceholderText = false
        outputDirectoryClearButton.isEnabled = true
        updateStartAvailability()
    }

    @objc private func clearSourceLibrary(_ sender: Any?) {
        sourceLibraryURL = nil
        sourceLibraryField.stringValue = L10n.xcframeworkNoSelection
        sourceLibraryField.showsPlaceholderText = true
        sourceLibraryClearButton.isEnabled = false
        updateStartAvailability()
    }

    @objc private func clearDeviceLibrary(_ sender: Any?) {
        deviceLibraryURL = nil
        deviceLibraryField.stringValue = L10n.xcframeworkUseSourceLibraryHint
        deviceLibraryField.showsPlaceholderText = true
        deviceLibraryClearButton.isEnabled = false
        updateStartAvailability()
    }

    @objc private func clearSimulatorLibrary(_ sender: Any?) {
        simulatorLibraryURL = nil
        simulatorLibraryField.stringValue = L10n.xcframeworkUseSourceLibraryHint
        simulatorLibraryField.showsPlaceholderText = true
        simulatorLibraryClearButton.isEnabled = false
        updateStartAvailability()
    }

    @objc private func clearMacCatalystLibrary(_ sender: Any?) {
        macCatalystLibraryURL = nil
        macCatalystLibraryField.stringValue = L10n.xcframeworkMacCatalystOptionalHint
        macCatalystLibraryField.showsPlaceholderText = true
        macCatalystLibraryClearButton.isEnabled = false
    }

    @objc private func clearHeadersDirectory(_ sender: Any?) {
        headersDirectoryURL = nil
        headersField.stringValue = L10n.xcframeworkNoSelection
        headersField.showsPlaceholderText = true
        headersClearButton.isEnabled = false
        updateStartAvailability()
    }

    @objc private func clearOutputDirectory(_ sender: Any?) {
        outputDirectoryURL = nil
        outputDirectoryField.stringValue = L10n.xcframeworkNoSelection
        outputDirectoryField.showsPlaceholderText = true
        outputDirectoryClearButton.isEnabled = false
        updateStartAvailability()
    }

    @objc private func startBuild(_ sender: Any?) {
        guard let effectiveSourceLibraryURL = resolvedSourceLibraryURL(),
              let headersDirectoryURL,
              let outputDirectoryURL else {
            return
        }

        let configuration = XCFrameworkBuildConfiguration(
            sourceLibraryURL: effectiveSourceLibraryURL,
            iosDeviceSourceLibraryURL: deviceLibraryURL,
            iosSimulatorSourceLibraryURL: simulatorLibraryURL,
            macCatalystSourceLibraryURL: macCatalystLibraryURL,
            headersDirectoryURL: headersDirectoryURL,
            outputDirectoryURL: outputDirectoryURL,
            outputLibraryName: outputLibraryNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty(or: "libSDK.a"),
            xcframeworkName: xcframeworkNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty(or: "SDK.xcframework"),
            moduleName: moduleNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            umbrellaHeader: umbrellaHeaderField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            macCatalystMinimumVersion: minVersionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty(or: "13.1"),
            macCatalystSDKVersion: sdkVersionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty(or: "17.5")
        )

        setRunning(true)
        logTextView.string = ""
        statusLabel.stringValue = L10n.xcframeworkRunningStatus

        do {
            try buildService.startBuild(
                configuration: configuration,
                outputHandler: { [weak self] chunk in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.logTextView.string += chunk
                        self.logTextView.scrollToEndOfDocument(nil)
                    }
                },
                completionHandler: { [weak self] result in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.setRunning(false)
                        switch result {
                        case let .success(url):
                            self.statusLabel.stringValue = L10n.xcframeworkCompletedStatus(path: url.path)
                        case let .failure(error):
                            self.appendErrorToLogIfNeeded(error)
                            self.statusLabel.stringValue = self.compactStatusMessage(for: error)
                            if error.localizedDescription != "XCFramework build cancelled." {
                                self.presentErrorAlert(error)
                            }
                        }
                    }
                }
            )
        } catch {
            setRunning(false)
            appendErrorToLogIfNeeded(error)
            statusLabel.stringValue = compactStatusMessage(for: error)
            presentErrorAlert(error)
        }
    }

    @objc private func cancelBuild(_ sender: Any?) {
        buildService.cancel()
        setRunning(false)
        statusLabel.stringValue = L10n.xcframeworkCancelledStatus
    }

    private func chooseFile(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: view.window ?? NSApp.mainWindow ?? NSWindow()) { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }

    private func chooseDirectory(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: view.window ?? NSApp.mainWindow ?? NSWindow()) { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }

    private func buildUI() {
        helpTitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        helpTextLabel.maximumNumberOfLines = 0

        [
            sourceLibraryField,
            deviceLibraryField,
            simulatorLibraryField,
            macCatalystLibraryField,
            headersField,
            outputDirectoryField,
        ].forEach {
            $0.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            $0.textColor = .secondaryLabelColor
            $0.lineBreakMode = .byTruncatingMiddle
            $0.maximumNumberOfLines = 1
        }
        [
            outputLibraryNameField,
            xcframeworkNameField,
            moduleNameField,
            umbrellaHeaderField,
            minVersionField,
            sdkVersionField,
        ].forEach(configureInputField)

        sourceLibraryField.acceptedContent = .file
        sourceLibraryField.onURLDropped = { [weak self] in self?.applySourceLibrary($0) }
        deviceLibraryField.acceptedContent = .file
        deviceLibraryField.onURLDropped = { [weak self] in self?.applyDeviceLibrary($0) }
        simulatorLibraryField.acceptedContent = .file
        simulatorLibraryField.onURLDropped = { [weak self] in self?.applySimulatorLibrary($0) }
        macCatalystLibraryField.acceptedContent = .file
        macCatalystLibraryField.onURLDropped = { [weak self] in self?.applyMacCatalystLibrary($0) }
        headersField.acceptedContent = .directory
        headersField.onURLDropped = { [weak self] in self?.applyHeadersDirectory($0) }
        outputDirectoryField.acceptedContent = .directory
        outputDirectoryField.onURLDropped = { [weak self] in self?.applyOutputDirectory($0) }

        logTitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let formStack = NSStackView(views: [
            helpTitleLabel,
            helpTextLabel,
            makeRow(label: sourceLibraryLabel, control: makeChooserStack(field: sourceLibraryField, chooseButton: sourceLibraryButton, clearButton: sourceLibraryClearButton, chooseAction: #selector(chooseSourceLibrary(_:)))),
            makeRow(label: deviceLibraryLabel, control: makeChooserStack(field: deviceLibraryField, chooseButton: deviceLibraryButton, clearButton: deviceLibraryClearButton, chooseAction: #selector(chooseDeviceLibrary(_:)))),
            makeRow(label: simulatorLibraryLabel, control: makeChooserStack(field: simulatorLibraryField, chooseButton: simulatorLibraryButton, clearButton: simulatorLibraryClearButton, chooseAction: #selector(chooseSimulatorLibrary(_:)))),
            makeRow(label: macCatalystLibraryLabel, control: makeChooserStack(field: macCatalystLibraryField, chooseButton: macCatalystLibraryButton, clearButton: macCatalystLibraryClearButton, chooseAction: #selector(chooseMacCatalystLibrary(_:)))),
            makeRow(label: headersLabel, control: makeChooserStack(field: headersField, chooseButton: headersButton, clearButton: headersClearButton, chooseAction: #selector(chooseHeadersDirectory(_:)))),
            makeRow(label: outputDirectoryLabel, control: makeChooserStack(field: outputDirectoryField, chooseButton: outputDirectoryButton, clearButton: outputDirectoryClearButton, chooseAction: #selector(chooseOutputDirectory(_:)))),
            makeRow(label: outputLibraryNameLabel, control: outputLibraryNameField),
            makeRow(label: xcframeworkNameLabel, control: xcframeworkNameField),
            makeRow(label: moduleNameLabel, control: moduleNameField),
            makeRow(label: umbrellaHeaderLabel, control: umbrellaHeaderField),
            makeRow(label: minVersionLabel, control: minVersionField),
            makeRow(label: sdkVersionLabel, control: sdkVersionField),
        ])
        formStack.orientation = .vertical
        formStack.alignment = .leading
        formStack.spacing = 12

        let allLabels = [
            sourceLibraryLabel,
            deviceLibraryLabel,
            simulatorLibraryLabel,
            macCatalystLibraryLabel,
            headersLabel,
            outputDirectoryLabel,
            outputLibraryNameLabel,
            xcframeworkNameLabel,
            moduleNameLabel,
            umbrellaHeaderLabel,
            minVersionLabel,
            sdkVersionLabel,
        ]
        allLabels.forEach {
            $0.setContentHuggingPriority(.required, for: .horizontal)
            $0.setContentCompressionResistancePriority(.required, for: .horizontal)
            $0.snp.makeConstraints { make in
                make.width.equalTo(180)
            }
        }

        logTextView.isEditable = false
        logTextView.isSelectable = true
        logTextView.drawsBackground = false
        logTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.isHorizontallyResizable = false
        logTextView.textContainer?.widthTracksTextView = true
        logTextView.textContainerInset = NSSize(width: 4, height: 8)

        let logScrollView = NSScrollView()
        logScrollView.drawsBackground = false
        logScrollView.hasVerticalScroller = true
        logScrollView.autohidesScrollers = true
        logScrollView.documentView = logTextView

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.isIndeterminate = true
        progressIndicator.isDisplayedWhenStopped = false

        startButton.target = self
        startButton.action = #selector(startBuild(_:))
        cancelButton.target = self
        cancelButton.action = #selector(cancelBuild(_:))
        sourceLibraryClearButton.target = self
        sourceLibraryClearButton.action = #selector(clearSourceLibrary(_:))
        deviceLibraryClearButton.target = self
        deviceLibraryClearButton.action = #selector(clearDeviceLibrary(_:))
        simulatorLibraryClearButton.target = self
        simulatorLibraryClearButton.action = #selector(clearSimulatorLibrary(_:))
        macCatalystLibraryClearButton.target = self
        macCatalystLibraryClearButton.action = #selector(clearMacCatalystLibrary(_:))
        headersClearButton.target = self
        headersClearButton.action = #selector(clearHeadersDirectory(_:))
        outputDirectoryClearButton.target = self
        outputDirectoryClearButton.action = #selector(clearOutputDirectory(_:))

        let statusRow = NSStackView(views: [progressIndicator, statusLabel, NSView()])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8
        statusLabel.maximumNumberOfLines = 1
        statusLabel.lineBreakMode = .byTruncatingMiddle

        let buttonRow = NSStackView(views: [startButton, cancelButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let container = NSStackView(views: [formStack, logTitleLabel, logScrollView, statusRow, buttonRow])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 14
        
        let contentView = NSView()
        contentView.addSubview(container)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = contentView
        view.addSubview(scrollView)

        [
            outputLibraryNameField,
            xcframeworkNameField,
            moduleNameField,
            umbrellaHeaderField,
        ].forEach {
            $0.snp.makeConstraints { make in
                make.width.equalTo(320)
            }
        }
        [minVersionField, sdkVersionField].forEach {
            $0.snp.makeConstraints { make in
                make.width.equalTo(320)
            }
        }
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        contentView.snp.makeConstraints { make in
            make.top.equalTo(scrollView.contentView)
            make.leading.equalTo(scrollView.contentView)
            make.trailing.equalTo(scrollView.contentView)
            make.bottom.equalTo(scrollView.contentView)
            make.width.equalTo(scrollView.contentView)
        }
        container.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(20)
        }
        logScrollView.snp.makeConstraints { make in
            make.width.equalTo(container)
            make.height.equalTo(240)
        }
    }

    private func makeChooserStack(field: NSTextField, chooseButton: NSButton, clearButton: NSButton, chooseAction: Selector) -> NSStackView {
        chooseButton.target = self
        chooseButton.action = chooseAction
        chooseButton.controlSize = .small
        clearButton.controlSize = .small
        [chooseButton, clearButton].forEach {
            $0.setContentHuggingPriority(.required, for: .horizontal)
            $0.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let stack = NSStackView(views: [field, chooseButton, clearButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        field.snp.makeConstraints { make in
            make.width.greaterThanOrEqualTo(420)
            make.height.greaterThanOrEqualTo(DropReceivingPathLabelLayoutMetrics.minimumHeight)
        }
        [chooseButton, clearButton].forEach { button in
            button.snp.makeConstraints { make in
                make.width.equalTo(84)
            }
        }
        clearButton.isEnabled = false
        return stack
    }

    private func configureInputField(_ field: NSTextField) {
        field.controlSize = .small
        field.font = NSFont.systemFont(ofSize: 12)
        field.snp.makeConstraints { make in
            make.height.equalTo(26)
        }
    }

    private func compactStatusMessage(for error: Error) -> String {
        let firstLine = error.localizedDescription
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        return firstLine ?? L10n.xcframeworkErrorTitle
    }

    private func appendErrorToLogIfNeeded(_ error: Error) {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.isEmpty == false else { return }
        if logTextView.string.isEmpty == false, logTextView.string.hasSuffix("\n") == false {
            logTextView.string += "\n"
        }
        logTextView.string += message + "\n"
        logTextView.scrollToEndOfDocument(nil)
    }

    private func applyIdleState() {
        sourceLibraryField.stringValue = L10n.xcframeworkNoSelection
        sourceLibraryField.showsPlaceholderText = true
        sourceLibraryClearButton.isEnabled = false
        deviceLibraryField.stringValue = L10n.xcframeworkUseSourceLibraryHint
        deviceLibraryField.showsPlaceholderText = true
        deviceLibraryClearButton.isEnabled = false
        simulatorLibraryField.stringValue = L10n.xcframeworkUseSourceLibraryHint
        simulatorLibraryField.showsPlaceholderText = true
        simulatorLibraryClearButton.isEnabled = false
        macCatalystLibraryField.stringValue = L10n.xcframeworkMacCatalystOptionalHint
        macCatalystLibraryField.showsPlaceholderText = true
        macCatalystLibraryClearButton.isEnabled = false
        headersField.stringValue = L10n.xcframeworkNoSelection
        headersField.showsPlaceholderText = true
        headersClearButton.isEnabled = false
        outputDirectoryField.stringValue = L10n.xcframeworkNoSelection
        outputDirectoryField.showsPlaceholderText = true
        outputDirectoryClearButton.isEnabled = false
        statusLabel.stringValue = L10n.xcframeworkIdleStatus
        setRunning(false)
    }

    private func updateStartAvailability() {
        startButton.isEnabled = resolvedSourceLibraryURL() != nil && headersDirectoryURL != nil && outputDirectoryURL != nil
    }

    private func setRunning(_ running: Bool) {
        [sourceLibraryButton, deviceLibraryButton, simulatorLibraryButton, macCatalystLibraryButton, headersButton, outputDirectoryButton].forEach {
            $0.isEnabled = !running
        }
        sourceLibraryClearButton.isEnabled = !running && sourceLibraryURL != nil
        deviceLibraryClearButton.isEnabled = !running && deviceLibraryURL != nil
        simulatorLibraryClearButton.isEnabled = !running && simulatorLibraryURL != nil
        macCatalystLibraryClearButton.isEnabled = !running && macCatalystLibraryURL != nil
        headersClearButton.isEnabled = !running && headersDirectoryURL != nil
        outputDirectoryClearButton.isEnabled = !running && outputDirectoryURL != nil
        [outputLibraryNameField, xcframeworkNameField, moduleNameField, umbrellaHeaderField, minVersionField, sdkVersionField].forEach {
            $0.isEnabled = !running
        }
        startButton.isEnabled = !running && resolvedSourceLibraryURL() != nil && headersDirectoryURL != nil && outputDirectoryURL != nil
        cancelButton.isEnabled = running
        if running {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
    }

    private func resolvedSourceLibraryURL() -> URL? {
        sourceLibraryURL ?? deviceLibraryURL ?? simulatorLibraryURL
    }

    private func presentErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.xcframeworkErrorTitle
        alert.informativeText = error.localizedDescription
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

private extension String {
    func nonEmpty(or fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }

    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

enum DropReceivingPathLabelColorToken: Equatable {
    case accentBorder
    case subtleAccentBorder
    case separatorBorder
    case accentFillLight
    case accentFillDark
    case subtleAccentFill
    case elevatedSurfaceFill
    case primaryText
    case secondaryText
}

struct DropReceivingPathLabelResolvedStyle: Equatable {
    let border: DropReceivingPathLabelColorToken
    let background: DropReceivingPathLabelColorToken
    let text: DropReceivingPathLabelColorToken
}

enum DropReceivingPathLabelLayoutMetrics {
    static let contentInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
    static let minimumHeight: CGFloat = 34
}

enum DropReceivingPathLabelStyleResolver {
    static func resolve(isDark: Bool, highlighted: Bool, showsPlaceholderText: Bool) -> DropReceivingPathLabelResolvedStyle {
        let border: DropReceivingPathLabelColorToken
        let background: DropReceivingPathLabelColorToken

        if highlighted {
            border = .accentBorder
            background = isDark ? .accentFillDark : .accentFillLight
        } else {
            border = isDark ? .separatorBorder : .subtleAccentBorder
            background = isDark ? .elevatedSurfaceFill : .subtleAccentFill
        }

        return DropReceivingPathLabelResolvedStyle(
            border: border,
            background: background,
            text: showsPlaceholderText ? .secondaryText : .primaryText
        )
    }

    static func color(for token: DropReceivingPathLabelColorToken) -> NSColor {
        switch token {
        case .accentBorder:
            return .controlAccentColor
        case .subtleAccentBorder:
            return .controlAccentColor.withAlphaComponent(0.35)
        case .separatorBorder:
            return .separatorColor
        case .accentFillLight:
            return .controlAccentColor.withAlphaComponent(0.12)
        case .accentFillDark:
            return .controlAccentColor.withAlphaComponent(0.18)
        case .subtleAccentFill:
            return .controlAccentColor.withAlphaComponent(0.08)
        case .elevatedSurfaceFill:
            return .controlBackgroundColor.withAlphaComponent(0.88)
        case .primaryText:
            return .labelColor
        case .secondaryText:
            return .secondaryLabelColor
        }
    }
}

@MainActor
private final class DropReceivingPathLabel: NSTextField {
    enum AcceptedContent {
        case file
        case directory
    }

    var acceptedContent: AcceptedContent = .file
    var onURLDropped: ((URL) -> Void)?
    var showsPlaceholderText = true {
        didSet {
            applyAppearance()
        }
    }

    private var isDropTargetHighlighted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = PaddedTextFieldCell(textCell: "")
        isEditable = false
        isSelectable = true
        isBordered = false
        drawsBackground = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        lineBreakMode = .byTruncatingMiddle
        maximumNumberOfLines = 1
        registerForDraggedTypes([.fileURL])
        applyAppearance()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard firstAcceptedURL(from: sender) != nil else { return [] }
        isDropTargetHighlighted = true
        applyAppearance()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTargetHighlighted = false
        applyAppearance()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = firstAcceptedURL(from: sender) else { return false }
        isDropTargetHighlighted = false
        applyAppearance()
        onURLDropped?(url)
        return true
    }

    override var acceptsFirstResponder: Bool { true }

    @objc func copy(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedString() ?? stringValue, forType: .string)
    }

    override func selectAll(_ sender: Any?) {
        selectText(sender)
    }

    private func firstAcceptedURL(from sender: NSDraggingInfo) -> URL? {
        guard
            let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        else {
            return nil
        }

        return urls.first { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            switch acceptedContent {
            case .file:
                return isDirectory == false
            case .directory:
                return isDirectory == true
            }
        }
    }

    private func applyAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let style = DropReceivingPathLabelStyleResolver.resolve(
            isDark: isDark,
            highlighted: isDropTargetHighlighted,
            showsPlaceholderText: showsPlaceholderText
        )
        layer?.borderColor = DropReceivingPathLabelStyleResolver.color(for: style.border).cgColor
        layer?.backgroundColor = DropReceivingPathLabelStyleResolver.color(for: style.background).cgColor
        textColor = DropReceivingPathLabelStyleResolver.color(for: style.text)
    }

    private func selectedString() -> String? {
        guard
            let editor = currentEditor(),
            editor.selectedRange.length > 0
        else {
            return nil
        }
        return (stringValue as NSString).substring(with: editor.selectedRange)
    }
}

private final class PaddedTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        insetRect(rect, by: DropReceivingPathLabelLayoutMetrics.contentInsets)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        drawingRect(forBounds: rect)
    }

    override func edit(withFrame aRect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(
            withFrame: drawingRect(forBounds: aRect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(withFrame aRect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(
            withFrame: drawingRect(forBounds: aRect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }

    override func cellSize(forBounds rect: NSRect) -> NSSize {
        var size = super.cellSize(forBounds: drawingRect(forBounds: rect))
        size.width += DropReceivingPathLabelLayoutMetrics.contentInsets.left + DropReceivingPathLabelLayoutMetrics.contentInsets.right
        size.height += DropReceivingPathLabelLayoutMetrics.contentInsets.top + DropReceivingPathLabelLayoutMetrics.contentInsets.bottom
        return size
    }

    private func insetRect(_ rect: NSRect, by insets: NSEdgeInsets) -> NSRect {
        NSRect(
            x: rect.origin.x + insets.left,
            y: rect.origin.y + insets.bottom,
            width: max(0, rect.size.width - insets.left - insets.right),
            height: max(0, rect.size.height - insets.top - insets.bottom)
        )
    }
}

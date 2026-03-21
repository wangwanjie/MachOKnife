import AppKit

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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.xcframeworkWindowTitle
        window.contentViewController = viewController
        super.init(window: window)
        self.window?.tabbingMode = .disallowed
        self.window?.minSize = NSSize(width: 720, height: 620)
        self.window?.title = L10n.xcframeworkWindowTitle
        if let window = self.window {
            if !window.setFrameUsingName(Self.autosaveName) {
                window.center()
            }
            window.setFrameAutosaveName(Self.autosaveName)
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
            self?.reloadLocalization()
        }
    }
}

@MainActor
private final class XCFrameworkBuildViewController: NSViewController {
    private let buildService = XCFrameworkBuildService()

    private let sourceLibraryLabel = makeSectionLabel("")
    private let sourceLibraryField = NSTextField(wrappingLabelWithString: "")
    private let sourceLibraryButton = NSButton(title: "", target: nil, action: nil)
    private let deviceLibraryLabel = makeSectionLabel("")
    private let deviceLibraryField = NSTextField(wrappingLabelWithString: "")
    private let deviceLibraryButton = NSButton(title: "", target: nil, action: nil)
    private let simulatorLibraryLabel = makeSectionLabel("")
    private let simulatorLibraryField = NSTextField(wrappingLabelWithString: "")
    private let simulatorLibraryButton = NSButton(title: "", target: nil, action: nil)
    private let headersLabel = makeSectionLabel("")
    private let headersField = NSTextField(wrappingLabelWithString: "")
    private let headersButton = NSButton(title: "", target: nil, action: nil)
    private let outputDirectoryLabel = makeSectionLabel("")
    private let outputDirectoryField = NSTextField(wrappingLabelWithString: "")
    private let outputDirectoryButton = NSButton(title: "", target: nil, action: nil)
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
        sourceLibraryLabel.stringValue = L10n.xcframeworkSourceLibraryLabel
        deviceLibraryLabel.stringValue = L10n.xcframeworkDeviceLibraryLabel
        simulatorLibraryLabel.stringValue = L10n.xcframeworkSimulatorLibraryLabel
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
        deviceLibraryButton.title = L10n.xcframeworkChooseFile
        simulatorLibraryButton.title = L10n.xcframeworkChooseFile
        headersButton.title = L10n.xcframeworkChooseDirectory
        outputDirectoryButton.title = L10n.xcframeworkChooseDirectory
        startButton.title = L10n.xcframeworkStart
        cancelButton.title = L10n.xcframeworkCancel
        if statusLabel.stringValue.isEmpty {
            statusLabel.stringValue = L10n.xcframeworkIdleStatus
        }
    }

    @objc private func chooseSourceLibrary(_ sender: Any?) {
        chooseFile { [weak self] url in
            self?.sourceLibraryURL = url
            self?.sourceLibraryField.stringValue = url.path
            if self?.deviceLibraryURL == nil {
                self?.deviceLibraryField.stringValue = L10n.xcframeworkUseSourceLibraryHint
            }
            if self?.simulatorLibraryURL == nil {
                self?.simulatorLibraryField.stringValue = L10n.xcframeworkUseSourceLibraryHint
            }
            self?.updateStartAvailability()
        }
    }

    @objc private func chooseDeviceLibrary(_ sender: Any?) {
        chooseFile { [weak self] url in
            self?.deviceLibraryURL = url
            self?.deviceLibraryField.stringValue = url.path
        }
    }

    @objc private func chooseSimulatorLibrary(_ sender: Any?) {
        chooseFile { [weak self] url in
            self?.simulatorLibraryURL = url
            self?.simulatorLibraryField.stringValue = url.path
        }
    }

    @objc private func chooseHeadersDirectory(_ sender: Any?) {
        chooseDirectory { [weak self] url in
            self?.headersDirectoryURL = url
            self?.headersField.stringValue = url.path
            self?.updateStartAvailability()
        }
    }

    @objc private func chooseOutputDirectory(_ sender: Any?) {
        chooseDirectory { [weak self] url in
            self?.outputDirectoryURL = url
            self?.outputDirectoryField.stringValue = url.path
            self?.updateStartAvailability()
        }
    }

    @objc private func startBuild(_ sender: Any?) {
        guard let sourceLibraryURL, let headersDirectoryURL, let outputDirectoryURL else {
            return
        }

        let configuration = XCFrameworkBuildConfiguration(
            sourceLibraryURL: sourceLibraryURL,
            iosDeviceSourceLibraryURL: deviceLibraryURL,
            iosSimulatorSourceLibraryURL: simulatorLibraryURL,
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
                            self.statusLabel.stringValue = error.localizedDescription
                            if error.localizedDescription != "XCFramework build cancelled." {
                                self.presentErrorAlert(error)
                            }
                        }
                    }
                }
            )
        } catch {
            setRunning(false)
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
        [sourceLibraryField, deviceLibraryField, simulatorLibraryField, headersField, outputDirectoryField].forEach {
            $0.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            $0.textColor = .secondaryLabelColor
        }

        logTitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let formStack = NSStackView(views: [
            makeRow(label: sourceLibraryLabel, control: makeChooserStack(field: sourceLibraryField, button: sourceLibraryButton, action: #selector(chooseSourceLibrary(_:)))),
            makeRow(label: deviceLibraryLabel, control: makeChooserStack(field: deviceLibraryField, button: deviceLibraryButton, action: #selector(chooseDeviceLibrary(_:)))),
            makeRow(label: simulatorLibraryLabel, control: makeChooserStack(field: simulatorLibraryField, button: simulatorLibraryButton, action: #selector(chooseSimulatorLibrary(_:)))),
            makeRow(label: headersLabel, control: makeChooserStack(field: headersField, button: headersButton, action: #selector(chooseHeadersDirectory(_:)))),
            makeRow(label: outputDirectoryLabel, control: makeChooserStack(field: outputDirectoryField, button: outputDirectoryButton, action: #selector(chooseOutputDirectory(_:)))),
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
        formStack.translatesAutoresizingMaskIntoConstraints = false

        logTextView.isEditable = false
        logTextView.isSelectable = true
        logTextView.drawsBackground = false
        logTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        let logScrollView = NSScrollView()
        logScrollView.translatesAutoresizingMaskIntoConstraints = false
        logScrollView.drawsBackground = false
        logScrollView.hasVerticalScroller = true
        logScrollView.documentView = logTextView

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.isIndeterminate = true
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        startButton.target = self
        startButton.action = #selector(startBuild(_:))
        cancelButton.target = self
        cancelButton.action = #selector(cancelBuild(_:))

        let statusRow = NSStackView(views: [progressIndicator, statusLabel, NSView()])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8
        statusRow.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [startButton, cancelButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let container = NSStackView(views: [formStack, logTitleLabel, logScrollView, statusRow, buttonRow])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 14
        container.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(container)

        NSLayoutConstraint.activate([
            outputLibraryNameField.widthAnchor.constraint(equalToConstant: 240),
            xcframeworkNameField.widthAnchor.constraint(equalToConstant: 240),
            moduleNameField.widthAnchor.constraint(equalToConstant: 240),
            umbrellaHeaderField.widthAnchor.constraint(equalToConstant: 240),
            minVersionField.widthAnchor.constraint(equalToConstant: 160),
            sdkVersionField.widthAnchor.constraint(equalToConstant: 160),
            logScrollView.heightAnchor.constraint(equalToConstant: 240),

            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            container.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),
        ])
    }

    private func makeChooserStack(field: NSTextField, button: NSButton, action: Selector) -> NSStackView {
        button.target = self
        button.action = action
        let stack = NSStackView(views: [field, button])
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 8
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true
        return stack
    }

    private func applyIdleState() {
        sourceLibraryField.stringValue = L10n.xcframeworkNoSelection
        deviceLibraryField.stringValue = L10n.xcframeworkUseSourceLibraryHint
        simulatorLibraryField.stringValue = L10n.xcframeworkUseSourceLibraryHint
        headersField.stringValue = L10n.xcframeworkNoSelection
        outputDirectoryField.stringValue = L10n.xcframeworkNoSelection
        statusLabel.stringValue = L10n.xcframeworkIdleStatus
        setRunning(false)
    }

    private func updateStartAvailability() {
        startButton.isEnabled = sourceLibraryURL != nil && headersDirectoryURL != nil && outputDirectoryURL != nil
    }

    private func setRunning(_ running: Bool) {
        [sourceLibraryButton, deviceLibraryButton, simulatorLibraryButton, headersButton, outputDirectoryButton].forEach {
            $0.isEnabled = !running
        }
        [outputLibraryNameField, xcframeworkNameField, moduleNameField, umbrellaHeaderField, minVersionField, sdkVersionField].forEach {
            $0.isEnabled = !running
        }
        startButton.isEnabled = !running && sourceLibraryURL != nil && headersDirectoryURL != nil && outputDirectoryURL != nil
        cancelButton.isEnabled = running
        if running {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
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

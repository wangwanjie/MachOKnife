import AppKit
import MachOKnifeKit
import SnapKit

@MainActor
final class BinaryContaminationWindowController: NSWindowController {
    private static let autosaveName = NSWindow.FrameAutosaveName("MachOKnifeContaminationWindowFrame")
    private let rootViewController: BinaryContaminationViewController
    private var settingsObserver: NSObjectProtocol?

    convenience init() {
        self.init(viewController: BinaryContaminationViewController())
    }

    private init(viewController: BinaryContaminationViewController) {
        self.rootViewController = viewController
        let defaultSize = NSSize(width: 780, height: 660)
        let minimumSize = NSSize(width: 660, height: 520)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.contaminationWindowTitle
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
        window?.title = L10n.contaminationWindowTitle
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
private final class BinaryContaminationViewController: NSViewController, NSComboBoxDelegate, NSTextFieldDelegate {
    private let service = BinaryContaminationCheckService()
    private let platformOptions = ["iphoneos", "iphonesimulator", "maccatalyst", "macos", "tvos", "watchos", "xros"]
    private let architectureOptions = ["arm64", "arm64e", "x86_64", "i386", "armv7", "armv7s"]

    private let inputLabel = makeSectionLabel("")
    private let chooseButton = NSButton(title: "", target: nil, action: nil)
    private let clearButton = NSButton(title: "", target: nil, action: nil)
    private let inputPathLabel = makeCopyablePathLabel()
    private let dropView = ToolDropZoneView()
    private let modeLabel = makeSectionLabel("")
    private let modePopUpButton = NSPopUpButton()
    private let targetLabel = makeSectionLabel("")
    private let targetComboBox = NSComboBox()
    private let analyzeButton = NSButton(title: "", target: nil, action: nil)
    private let reportLabel = NSTextField(labelWithString: "")
    private let reportTextView = NSTextView()

    private var inputURL: URL?

    override func loadView() {
        view = AdaptiveBackgroundView(backgroundColor: .windowBackgroundColor)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reloadLocalization()
    }

    func reloadLocalization() {
        inputLabel.stringValue = L10n.contaminationInputLabel
        chooseButton.title = L10n.summaryChooseInput
        clearButton.title = L10n.mergeSplitMergeClear
        modeLabel.stringValue = L10n.contaminationModeLabel
        targetLabel.stringValue = L10n.contaminationTargetLabel
        analyzeButton.title = L10n.contaminationAnalyze
        reportLabel.stringValue = L10n.contaminationReportTitle
        inputPathLabel.stringValue = inputURL?.path ?? L10n.xcframeworkNoSelection
        dropView.titleLabel.stringValue = L10n.summaryDropHint

        rebuildModeOptions()
        if reportTextView.string.isEmpty {
            reportTextView.string = L10n.contaminationIdleStatus
            refreshReportLayout()
        }
    }

    @objc private func chooseInput(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: view.window ?? NSApp.mainWindow ?? NSWindow()) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadInput(url)
        }
    }

    @objc private func clearInput(_ sender: Any?) {
        inputURL = nil
        inputPathLabel.stringValue = L10n.xcframeworkNoSelection
        reportTextView.string = L10n.contaminationIdleStatus
        refreshReportLayout()
        clearButton.isEnabled = false
    }

    @objc private func modeChanged(_ sender: Any?) {
        rebuildTargetOptions()
        runCheckIfPossible(presentingErrors: false)
    }

    @objc private func runCheck(_ sender: Any?) {
        runCheckIfPossible(presentingErrors: true)
    }

    @objc private func targetChanged(_ sender: Any?) {
        runCheckIfPossible(presentingErrors: false)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as? NSComboBox === targetComboBox else { return }
        runCheckIfPossible(presentingErrors: false)
    }

    private func runCheckIfPossible(presentingErrors: Bool) {
        guard let inputURL else { return }
        let target = targetComboBox.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard target.isEmpty == false else { return }

        do {
            let report = try service.runCheck(
                at: inputURL,
                target: target,
                mode: selectedMode
            )
            reportTextView.string = report.renderedText
            refreshReportLayout()
        } catch {
            reportTextView.string = error.localizedDescription
            refreshReportLayout()
            if presentingErrors {
                presentContaminationAlert(error)
            }
        }
    }

    private var selectedMode: BinaryContaminationCheckMode {
        modePopUpButton.indexOfSelectedItem == 0 ? .platform : .architecture
    }

    private func buildUI() {
        chooseButton.target = self
        chooseButton.action = #selector(chooseInput(_:))
        clearButton.target = self
        clearButton.action = #selector(clearInput(_:))
        analyzeButton.target = self
        analyzeButton.action = #selector(runCheck(_:))
        modePopUpButton.target = self
        modePopUpButton.action = #selector(modeChanged(_:))
        targetComboBox.target = self
        targetComboBox.action = #selector(targetChanged(_:))
        targetComboBox.delegate = self

        clearButton.isEnabled = false

        dropView.onFileURLDropped = { [weak self] url in
            self?.loadInput(url)
        }

        targetComboBox.isEditable = true
        targetComboBox.completes = true

        reportTextView.isEditable = false
        reportTextView.isSelectable = true
        reportTextView.isRichText = false
        reportTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        reportTextView.drawsBackground = false
        reportTextView.minSize = .zero
        reportTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        reportTextView.isVerticallyResizable = true
        reportTextView.isHorizontallyResizable = false
        reportTextView.autoresizingMask = [.width]
        reportTextView.textContainer?.widthTracksTextView = true
        reportTextView.textContainer?.heightTracksTextView = false
        reportTextView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        reportTextView.textContainerInset = NSSize(width: 0, height: 6)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = reportTextView

        let controls = NSStackView()
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 12

        let inputRow = NSStackView(views: [inputLabel, NSView(), chooseButton, clearButton])
        inputRow.orientation = .horizontal
        inputRow.alignment = .centerY
        inputRow.spacing = 12

        let modeRow = makeRow(label: modeLabel, control: modePopUpButton)
        let targetRow = makeRow(label: targetLabel, control: targetComboBox)

        controls.addArrangedSubview(inputRow)
        controls.addArrangedSubview(inputPathLabel)
        controls.addArrangedSubview(dropView)
        controls.addArrangedSubview(modeRow)
        controls.addArrangedSubview(targetRow)
        controls.addArrangedSubview(analyzeButton)
        controls.addArrangedSubview(reportLabel)
        controls.addArrangedSubview(scrollView)
        view.addSubview(controls)

        controls.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(20)
        }
        dropView.snp.makeConstraints { make in
            make.width.equalTo(controls)
            make.height.equalTo(96)
        }
        targetComboBox.snp.makeConstraints { make in
            make.width.equalTo(220)
        }
        scrollView.snp.makeConstraints { make in
            make.width.equalTo(controls)
            make.height.greaterThanOrEqualTo(320)
        }
        reportTextView.snp.makeConstraints { make in
            make.width.equalTo(scrollView.contentView)
        }
    }

    private func rebuildModeOptions() {
        let titles = [L10n.contaminationModePlatform, L10n.contaminationModeArchitecture]
        let previousIndex = max(modePopUpButton.indexOfSelectedItem, 0)
        modePopUpButton.removeAllItems()
        modePopUpButton.addItems(withTitles: titles)
        modePopUpButton.selectItem(at: min(previousIndex, titles.count - 1))
        rebuildTargetOptions()
    }

    private func rebuildTargetOptions() {
        let previousValue = targetComboBox.stringValue
        targetComboBox.removeAllItems()
        targetComboBox.addItems(withObjectValues: selectedMode == .platform ? platformOptions : architectureOptions)
        targetComboBox.stringValue = previousValue.isEmpty
            ? (selectedMode == .platform ? platformOptions[0] : architectureOptions[0])
            : previousValue
    }

    private func loadInput(_ url: URL) {
        inputURL = url
        inputPathLabel.stringValue = url.path
        clearButton.isEnabled = true
        runCheckIfPossible(presentingErrors: false)
    }

    private func presentContaminationAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.contaminationErrorTitle
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.beginSheetModal(for: view.window ?? NSWindow())
    }

    private func refreshReportLayout() {
        guard let textContainer = reportTextView.textContainer else { return }
        reportTextView.layoutManager?.ensureLayout(for: textContainer)
        let usedRect = reportTextView.layoutManager?.usedRect(for: textContainer) ?? .zero
        reportTextView.frame.size.height = max(usedRect.height + reportTextView.textContainerInset.height * 2, 320)
    }
}

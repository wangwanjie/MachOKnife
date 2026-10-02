import AppKit
import MachOKnifeKit
import SnapKit

@MainActor
final class MachOSummaryWindowController: NSWindowController {
    private static let autosaveName = NSWindow.FrameAutosaveName("MachOKnifeSummaryWindowFrame")
    private let summaryViewController: MachOSummaryViewController
    private var settingsObserver: NSObjectProtocol?

    convenience init() {
        self.init(viewController: MachOSummaryViewController())
    }

    private init(viewController: MachOSummaryViewController) {
        self.summaryViewController = viewController
        let defaultSize = NSSize(width: 760, height: 620)
        let minimumSize = NSSize(width: 620, height: 460)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.summaryWindowTitle
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
        window?.title = L10n.summaryWindowTitle
        summaryViewController.reloadLocalization()
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
private final class MachOSummaryViewController: NSViewController {
    private let summaryService = BinarySummaryService()

    private let inputLabel = makeSectionLabel("")
    private let chooseButton = NSButton(title: "", target: nil, action: nil)
    private let clearButton = NSButton(title: "", target: nil, action: nil)
    private let pathLabel = makeCopyablePathLabel()
    private let dropView = ToolDropZoneView()
    private let reportLabel = NSTextField(labelWithString: "")
    private let reportTextView = NSTextView()

    private var inputURL: URL?
    private var report: ToolTextReport?
    /// The last analysis failure for `inputURL`, kept so a language change can re-render it
    /// without re-running the analysis or presenting the alert again.
    private var reportError: Error?

    override func loadView() {
        view = AdaptiveBackgroundView(backgroundColor: .windowBackgroundColor)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reloadLocalization()
    }

    func reloadLocalization() {
        inputLabel.stringValue = L10n.summaryInputLabel
        chooseButton.title = L10n.summaryChooseInput
        clearButton.title = L10n.mergeSplitMergeClear
        reportLabel.stringValue = L10n.summaryReportTitle
        dropView.titleLabel.stringValue = L10n.summaryDropHint
        pathLabel.stringValue = inputURL?.path ?? L10n.xcframeworkNoSelection

        renderReport()
    }

    private func renderReport() {
        if inputURL == nil {
            reportTextView.string = L10n.summaryIdleStatus
        } else if let report {
            reportTextView.string = report.renderedText
        } else if let reportError {
            reportTextView.string = reportError.localizedDescription
        } else {
            reportTextView.string = ""
        }
        refreshReportLayout()
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
        report = nil
        reportError = nil
        pathLabel.stringValue = L10n.xcframeworkNoSelection
        renderReport()
        clearButton.isEnabled = false
    }

    private func buildUI() {
        chooseButton.target = self
        chooseButton.action = #selector(chooseInput(_:))
        clearButton.target = self
        clearButton.action = #selector(clearInput(_:))

        clearButton.isEnabled = false

        dropView.onFileURLDropped = { [weak self] url in
            self?.loadInput(url)
        }

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

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12

        let inputRow = NSStackView(views: [inputLabel, NSView(), chooseButton, clearButton])
        inputRow.orientation = .horizontal
        inputRow.alignment = .centerY
        inputRow.spacing = 12

        contentStack.addArrangedSubview(inputRow)
        contentStack.addArrangedSubview(pathLabel)
        contentStack.addArrangedSubview(dropView)
        contentStack.addArrangedSubview(reportLabel)
        contentStack.addArrangedSubview(scrollView)
        view.addSubview(contentStack)

        contentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(20)
        }
        dropView.snp.makeConstraints { make in
            make.width.equalTo(contentStack)
            make.height.equalTo(96)
        }
        scrollView.snp.makeConstraints { make in
            make.width.equalTo(contentStack)
            make.height.greaterThanOrEqualTo(320)
        }
        reportTextView.snp.makeConstraints { make in
            make.width.equalTo(scrollView.contentView)
        }
    }

    private func loadInput(_ url: URL) {
        inputURL = url
        pathLabel.stringValue = url.path
        clearButton.isEnabled = true
        analyzeCurrentInput()
    }

    private func analyzeCurrentInput() {
        report = nil
        reportError = nil
        guard let inputURL else {
            renderReport()
            return
        }

        do {
            report = try summaryService.makeReport(for: inputURL)
            renderReport()
        } catch {
            reportError = error
            renderReport()
            presentSummaryAlert(error)
        }
    }

    private func refreshReportLayout() {
        guard let textContainer = reportTextView.textContainer else { return }
        reportTextView.layoutManager?.ensureLayout(for: textContainer)
        let usedRect = reportTextView.layoutManager?.usedRect(for: textContainer) ?? .zero
        reportTextView.frame.size.height = max(usedRect.height + reportTextView.textContainerInset.height * 2, 320)
    }

    private func presentSummaryAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.summaryErrorTitle
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.beginSheetModal(for: view.window ?? NSWindow())
    }
}

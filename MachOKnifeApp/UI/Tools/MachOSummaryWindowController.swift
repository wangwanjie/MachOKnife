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
            Task { @MainActor [weak self] in
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
    private let pathLabel = NSTextField(wrappingLabelWithString: "")
    private let dropView = ToolDropZoneView()
    private let reportLabel = NSTextField(labelWithString: "")
    private let reportTextView = NSTextView()

    private var inputURL: URL?
    private var report: ToolTextReport?

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
        reportLabel.stringValue = L10n.summaryReportTitle
        dropView.titleLabel.stringValue = L10n.summaryDropHint
        pathLabel.stringValue = inputURL?.path ?? L10n.xcframeworkNoSelection

        if inputURL != nil {
            analyzeCurrentInput()
        } else {
            reportTextView.string = L10n.summaryIdleStatus
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

    private func buildUI() {
        chooseButton.target = self
        chooseButton.action = #selector(chooseInput(_:))

        pathLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        pathLabel.textColor = .secondaryLabelColor

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
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = reportTextView

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let inputRow = NSStackView(views: [inputLabel, chooseButton])
        inputRow.orientation = .horizontal
        inputRow.alignment = .centerY
        inputRow.spacing = 12

        contentStack.addArrangedSubview(inputRow)
        contentStack.addArrangedSubview(pathLabel)
        contentStack.addArrangedSubview(dropView)
        contentStack.addArrangedSubview(reportLabel)
        contentStack.addArrangedSubview(scrollView)
        view.addSubview(contentStack)

        dropView.translatesAutoresizingMaskIntoConstraints = false
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
        analyzeCurrentInput()
    }

    private func analyzeCurrentInput() {
        guard let inputURL else {
            reportTextView.string = L10n.summaryIdleStatus
            return
        }

        do {
            let report = try summaryService.makeReport(for: inputURL)
            self.report = report
            reportTextView.string = report.renderedText
            refreshReportLayout()
        } catch {
            reportTextView.string = error.localizedDescription
            refreshReportLayout()
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

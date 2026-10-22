import AppKit
import MachOKnifeKit
import SnapKit

@MainActor
final class MachOSummaryWindowController: NSWindowController {
    private static let autosaveName = NSWindow.FrameAutosaveName("MachOKnifeSummaryWindowFrame")
    private let summaryViewController: MachOSummaryViewController
    private var settingsObserver: NSObjectProtocol?
    private var workspaceHandOff = WorkspaceToolHandOff()

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

    /// 载入并在后台分析指定文件（与拖放/选择文件的效果相同）。
    func loadInput(_ url: URL) {
        _ = window
        summaryViewController.loadInput(url)
    }

    /// 用主工作区当前打开的文件预填输入；用户已在本窗口手动选择了其他文件时保持不变。
    func prefill(withWorkspaceDocument url: URL) {
        _ = window
        guard let target = workspaceHandOff.inputToPrefill(
            workspaceDocumentURL: url,
            currentInputURL: summaryViewController.inputURL
        ) else {
            return
        }
        summaryViewController.loadInput(target)
    }

    /// 当前分析的输入文件。
    var inputURL: URL? {
        summaryViewController.inputURL
    }

    /// 是否有后台分析尚未完成。
    var isAnalyzing: Bool {
        summaryViewController.isAnalyzing
    }

    /// 报告区当前显示的文本。
    var reportText: String {
        summaryViewController.reportText
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
    private let inputLabel = makeSectionLabel("")
    private let chooseButton = NSButton(title: "", target: nil, action: nil)
    private let clearButton = NSButton(title: "", target: nil, action: nil)
    private let pathLabel = makeCopyablePathLabel()
    private let dropView = ToolDropZoneView()
    private let reportLabel = NSTextField(labelWithString: "")
    private let reportTextView = NSTextView()

    private(set) var inputURL: URL?
    private var report: ToolTextReport?
    /// The last analysis failure for `inputURL`, kept so a language change can re-render it
    /// without re-running the analysis or presenting the alert again.
    private var reportError: Error?
    /// 每次发起分析都会递增，用于丢弃已被新输入（或清除）取代的旧分析结果。
    private var analysisGeneration = 0
    private var analysisTask: Task<Void, Never>?

    /// 是否有后台分析正在进行（供测试和界面状态使用）。
    var isAnalyzing: Bool {
        analysisTask != nil
    }

    var reportText: String {
        reportTextView.string
    }

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
        } else if analysisTask != nil {
            reportTextView.string = L10n.summaryRunningStatus
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
        cancelAnalysis()
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

    func loadInput(_ url: URL) {
        inputURL = url
        pathLabel.stringValue = url.path
        clearButton.isEnabled = true
        analyzeCurrentInput()
    }

    private func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        analysisGeneration += 1
    }

    private func analyzeCurrentInput() {
        cancelAnalysis()
        report = nil
        reportError = nil
        guard let inputURL else {
            renderReport()
            return
        }

        let generation = analysisGeneration
        // 汇总报告需要遍历整个二进制/包（可能包含大量架构或静态库成员），
        // 放到后台执行，避免在主线程同步分析导致界面卡死。
        analysisTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<ToolTextReport, Error>
            do {
                result = .success(try BinarySummaryService().makeReport(for: inputURL))
            } catch {
                result = .failure(error)
            }
            guard Task.isCancelled == false else {
                return
            }
            await self?.applyAnalysisResult(result, generation: generation)
        }
        renderReport()
    }

    private func applyAnalysisResult(_ result: Result<ToolTextReport, Error>, generation: Int) {
        // 结果已过期（期间更换或清除了输入）则直接丢弃。
        guard generation == analysisGeneration else {
            return
        }
        analysisTask = nil

        switch result {
        case let .success(newReport):
            report = newReport
            renderReport()
        case let .failure(error):
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
        guard let window = view.window, window.isVisible else {
            // 分析在后台完成，届时窗口可能已关闭：错误原因已写入报告区，不再弹出无处附着的提示框
            // （原实现附着到临时创建的 NSWindow 上，实际上永远不可见）。
            return
        }
        alert.beginSheetModal(for: window)
    }
}

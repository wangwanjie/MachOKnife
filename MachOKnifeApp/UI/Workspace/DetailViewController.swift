import AppKit
import Combine

@MainActor
final class DetailViewController: NSViewController {
    var promptForDocument: (() -> Void)?

    private let viewModel: WorkspaceViewModel
    private let emptyStateTitleLabel = NSTextField(labelWithString: L10n.workspaceEmptyTitle)
    private let emptyStateSubtitleLabel = NSTextField(labelWithString: L10n.workspaceEmptySubtitle)
    private let openButton = NSButton(title: L10n.workspaceEmptyOpenButton, target: nil, action: nil)
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let dropView = WorkspaceDropView()
        dropView.onFileURLDropped = { [weak self] url in
            self?.viewModel.openDocument(at: url)
        }
        view = dropView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        bindViewModel()
    }

    @objc private func openFile(_ sender: Any?) {
        promptForDocument?()
    }

    private func buildUI() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        emptyStateTitleLabel.font = NSFont.systemFont(ofSize: 28, weight: .semibold)
        emptyStateTitleLabel.alignment = .center
        emptyStateTitleLabel.setAccessibilityIdentifier("workspace.empty.title")

        emptyStateSubtitleLabel.font = NSFont.systemFont(ofSize: 14)
        emptyStateSubtitleLabel.textColor = .secondaryLabelColor
        emptyStateSubtitleLabel.alignment = .center
        emptyStateSubtitleLabel.maximumNumberOfLines = 0
        emptyStateSubtitleLabel.lineBreakMode = .byWordWrapping

        openButton.bezelStyle = .rounded
        openButton.target = self
        openButton.action = #selector(openFile(_:))
        openButton.setAccessibilityIdentifier("workspace.empty.openButton")

        let emptyStack = NSStackView(views: [emptyStateTitleLabel, emptyStateSubtitleLabel, openButton])
        emptyStack.orientation = .vertical
        emptyStack.alignment = .centerX
        emptyStack.spacing = 14
        emptyStack.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.isHidden = true

        view.addSubview(emptyStack)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            emptyStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
        ])
    }

    private func bindViewModel() {
        Publishers.CombineLatest3(
            viewModel.$analysis
                .map { $0 != nil }
                .removeDuplicates(),
            viewModel.$detailText,
            viewModel.$errorMessage
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] hasLoadedDocument, detailText, errorMessage in
                guard let self else { return }

                if let errorMessage {
                    scrollView.isHidden = false
                    textView.string = errorMessage
                    emptyStateTitleLabel.superview?.isHidden = true
                    return
                }

                scrollView.isHidden = !hasLoadedDocument
                textView.string = detailText
                emptyStateTitleLabel.superview?.isHidden = hasLoadedDocument
            }
            .store(in: &cancellables)
    }
}

// Accepting file drops at the view boundary keeps drag-and-drop support local to
// the workspace instead of forcing the app delegate to inspect dragging state.
private final class WorkspaceDropView: NSView {
    var onFileURLDropped: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard
            let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]),
            let url = items.first as? URL
        else {
            return false
        }

        onFileURLDropped?(url)
        return true
    }
}

import AppKit
import Combine

@MainActor
final class InspectorViewController: NSViewController {
    private let viewModel: WorkspaceViewModel
    private let textView = NSTextView()
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
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        bindViewModel()
    }

    private func buildUI() {
        let titleLabel = NSTextField(labelWithString: "Inspector")
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = "Dependencies and rpaths will appear here."

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        view.addSubview(titleLabel)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    private func bindViewModel() {
        viewModel.$inspectorText
            .receive(on: RunLoop.main)
            .sink { [weak self] inspectorText in
                self?.textView.string = inspectorText.isEmpty ? "Dependencies and rpaths will appear here." : inspectorText
            }
            .store(in: &cancellables)
    }
}

import AppKit

@MainActor
final class WorkspaceSplitViewController: NSSplitViewController {
    var promptForDocument: (() -> Void)?
    var openDocument: ((URL) -> Void)?
    var copySelectedNodeInfo: (() -> Void)?
    var exportSelectedNodeInfo: (() -> Void)?
    private let sourceListViewController: SourceListViewController
    private let detailViewController: DetailViewController

    init(viewModel: WorkspaceViewModel) {
        self.sourceListViewController = SourceListViewController(viewModel: viewModel)
        self.detailViewController = DetailViewController(viewModel: viewModel)
        super.init(nibName: nil, bundle: nil)

        detailViewController.promptForDocument = { [weak self] in
            self?.promptForDocument?()
        }
        detailViewController.openDocument = { [weak self] url in
            self?.openDocument?(url)
        }
        sourceListViewController.copySelectedNodeInfo = { [weak self] in
            self?.copySelectedNodeInfo?()
        }
        sourceListViewController.exportSelectedNodeInfo = { [weak self] in
            self?.exportSelectedNodeInfo?()
        }

        let sourceItem = NSSplitViewItem(sidebarWithViewController: sourceListViewController)
        sourceItem.minimumThickness = 220
        sourceItem.maximumThickness = 420

        let detailItem = NSSplitViewItem(viewController: detailViewController)

        addSplitViewItem(sourceItem)
        addSplitViewItem(detailItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func selectPreviewInspectorTab() {
        // TODO: Reintroduce preview/retag-specific tooling as a separate tools window.
    }

    func reloadLocalization() {
        sourceListViewController.reloadLocalization()
        detailViewController.reloadLocalization()
    }
}

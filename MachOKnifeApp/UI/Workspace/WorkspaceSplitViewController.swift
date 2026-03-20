import AppKit

@MainActor
final class WorkspaceSplitViewController: NSSplitViewController {
    var promptForDocument: (() -> Void)?
    var openDocument: ((URL) -> Void)?
    private let inspectorViewController: InspectorViewController

    init(viewModel: WorkspaceViewModel) {
        self.inspectorViewController = InspectorViewController(viewModel: viewModel)
        super.init(nibName: nil, bundle: nil)

        let sourceListViewController = SourceListViewController(viewModel: viewModel)
        let detailViewController = DetailViewController(viewModel: viewModel)

        detailViewController.promptForDocument = { [weak self] in
            self?.promptForDocument?()
        }
        detailViewController.openDocument = { [weak self] url in
            self?.openDocument?(url)
        }

        let sourceItem = NSSplitViewItem(sidebarWithViewController: sourceListViewController)
        sourceItem.minimumThickness = 220
        sourceItem.maximumThickness = 360

        let detailItem = NSSplitViewItem(viewController: detailViewController)

        let inspectorItem = NSSplitViewItem(viewController: inspectorViewController)
        inspectorItem.minimumThickness = 260
        inspectorItem.maximumThickness = 420

        addSplitViewItem(sourceItem)
        addSplitViewItem(detailItem)
        addSplitViewItem(inspectorItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func selectPreviewInspectorTab() {
        inspectorViewController.selectPreviewTab()
    }
}

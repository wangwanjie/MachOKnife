import AppKit
import Combine
import MachOKnifeKit
import SnapKit

@MainActor
final class SourceListViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let viewModel: WorkspaceViewModel
    var copySelectedNodeInfo: (() -> Void)?
    var exportSelectedNodeInfo: (() -> Void)?
    private let outlineView = BrowserOutlineView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let documentSummaryLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let placeholderTitleLabel = NSTextField(labelWithString: "")
    private let placeholderSubtitleLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var contextMenu = makeContextMenu()
    private var allOutlineItems: [BrowserNode] = []
    private var outlineItems: [BrowserNode] = []
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
        view = AdaptiveBackgroundView(backgroundColor: .controlBackgroundColor)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        bindViewModel()
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let currentItem = item as? BrowserNode
        return currentItem?.childCount ?? outlineItems.count
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let item = item as? BrowserNode else { return false }
        return item.childCount > 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let currentItem = item as? BrowserNode
        return currentItem?.child(at: index) ?? outlineItems[index]
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? BrowserNode else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("SourceCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        if cell.textField == nil {
            let titleField = NSTextField(labelWithString: "")
            titleField.maximumNumberOfLines = 1
            titleField.usesSingleLineMode = true
            titleField.lineBreakMode = .byTruncatingMiddle
            titleField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            cell.addSubview(titleField)

            titleField.snp.makeConstraints { make in
                make.leading.trailing.equalToSuperview().inset(6)
                make.centerY.equalToSuperview()
            }
            cell.textField = titleField
        }

        cell.textField?.stringValue = item.title
        cell.toolTip = item.subtitle
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        BrowserOutlineRowView()
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? BrowserNode else { return }
        viewModel.selectBrowserNode(item)
    }

    func reloadLocalization() {
        titleLabel.stringValue = L10n.sourceListTitle
        searchField.placeholderString = L10n.sourceListSearchPlaceholder
        updateDocumentSummary()
        updatePlaceholder()
        contextMenu.items.first?.title = L10n.menuCopyNodeInfo
        contextMenu.items.last?.title = L10n.menuExportNodeInfo
        outlineView.reloadData()
    }

    @objc private func searchDidChange(_ sender: NSSearchField) {
        applyFilter(query: sender.stringValue)
    }

    private func buildUI() {
        titleLabel.stringValue = L10n.sourceListTitle
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        documentSummaryLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        documentSummaryLabel.textColor = .tertiaryLabelColor
        documentSummaryLabel.lineBreakMode = .byTruncatingMiddle
        documentSummaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        searchField.placeholderString = L10n.sourceListSearchPlaceholder
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchDidChange(_:))

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SourceColumn"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 22
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.floatsGroupRows = false
        outlineView.style = .sourceList
        outlineView.autoresizesOutlineColumn = true
        outlineView.menu = contextMenu
        outlineView.onPrepareContextMenu = { [weak self] row in
            self?.prepareContextMenu(forRow: row)
        }

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = outlineView

        placeholderTitleLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        placeholderTitleLabel.alignment = .center
        placeholderTitleLabel.textColor = .secondaryLabelColor

        placeholderSubtitleLabel.alignment = .center
        placeholderSubtitleLabel.textColor = .tertiaryLabelColor
        placeholderSubtitleLabel.maximumNumberOfLines = 0
        placeholderSubtitleLabel.lineBreakMode = .byWordWrapping

        let placeholderStack = NSStackView(views: [placeholderTitleLabel, placeholderSubtitleLabel])
        placeholderStack.orientation = .vertical
        placeholderStack.alignment = .centerX
        placeholderStack.spacing = 8
        placeholderStack.setAccessibilityIdentifier("workspace.sourceList.placeholder")

        view.addSubview(titleLabel)
        view.addSubview(documentSummaryLabel)
        view.addSubview(searchField)
        view.addSubview(scrollView)
        view.addSubview(placeholderStack)

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(12)
            make.leading.equalToSuperview().inset(14)
            make.trailing.lessThanOrEqualToSuperview().inset(14)
        }
        documentSummaryLabel.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.leading.equalTo(titleLabel.snp.trailing).offset(8)
            make.trailing.equalToSuperview().inset(14)
        }
        searchField.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview().inset(12)
        }
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(searchField.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview()
        }
        placeholderStack.snp.makeConstraints { make in
            make.center.equalTo(scrollView)
            make.leading.greaterThanOrEqualToSuperview().inset(20)
            make.trailing.lessThanOrEqualToSuperview().inset(20)
        }

        updatePlaceholder()
    }

    private func bindViewModel() {
        viewModel.$browserOutlineRootNodes
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                guard let self else { return }
                allOutlineItems = items
                applyFilter(query: searchField.stringValue)
                updateDocumentSummary()
                applySelection(viewModel.browserSelectedNodeID)
            }
            .store(in: &cancellables)

        viewModel.$browserSelectedNodeID
            .receive(on: RunLoop.main)
            .sink { [weak self] nodeID in
                self?.applySelection(nodeID)
            }
            .store(in: &cancellables)
    }

    private func applyFilter(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            outlineItems = allOutlineItems
        } else {
            outlineItems = allOutlineItems.compactMap { filter(node: $0, query: trimmedQuery) }
        }

        outlineView.reloadData()
        if trimmedQuery.isEmpty == false {
            outlineItems.forEach { outlineView.expandItem($0) }
        }
        updatePlaceholder()
    }

    private func applySelection(_ nodeID: String?) {
        guard let nodeID else {
            outlineView.deselectAll(nil)
            return
        }

        expandPath(to: nodeID, items: outlineItems)
        let targetRow = row(for: nodeID)
        guard targetRow != outlineView.selectedRow else { return }

        if targetRow >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
        } else {
            outlineView.deselectAll(nil)
        }
    }

    private func row(for nodeID: String) -> Int {
        for row in 0..<outlineView.numberOfRows {
            guard let item = outlineView.item(atRow: row) as? BrowserNode else {
                continue
            }
            if item.id == nodeID {
                return row
            }
        }

        return -1
    }

    @discardableResult
    private func expandPath(to nodeID: String, items: [BrowserNode]) -> Bool {
        for item in items {
            if item.id == nodeID {
                return true
            }
            if expandPath(to: nodeID, items: item.loadedChildren) {
                outlineView.expandItem(item)
                return true
            }
        }
        return false
    }

    private func filter(node: BrowserNode, query: String) -> BrowserNode? {
        let filteredChildren = node.loadedChildren.compactMap { filter(node: $0, query: query) }
        guard matches(node: node, query: query) || !filteredChildren.isEmpty else {
            return nil
        }

        return BrowserNode(
            id: node.id,
            title: node.title,
            subtitle: node.subtitle,
            summaryStyle: node.summaryStyle,
            detailCount: node.detailCount,
            indexedDetailProvider: { node.detailRow(at: $0) },
            children: filteredChildren,
            childCount: filteredChildren.count,
            rawAddress: node.rawAddress,
            rvaAddress: node.rvaAddress,
            dataRange: node.dataRange
        )
    }

    private func matches(node: BrowserNode, query: String) -> Bool {
        let detailPreviewRows = (0..<min(node.detailCount, 24)).map { node.detailRow(at: $0) }
        let haystack = [
            node.title,
            node.subtitle ?? "",
            detailPreviewRows.map(\.key).joined(separator: " "),
            detailPreviewRows.map(\.value).joined(separator: " "),
        ]
        .joined(separator: " ")
        .localizedLowercase
        return haystack.contains(query.localizedLowercase)
    }

    private func updatePlaceholder() {
        let hasDocument = !allOutlineItems.isEmpty
        let hasVisibleItems = !outlineItems.isEmpty
        placeholderTitleLabel.stringValue = hasDocument ? L10n.sourceListNoResults : L10n.sourceListEmptyTitle
        placeholderSubtitleLabel.stringValue = hasDocument ? "\"\(searchField.stringValue)\"" : L10n.sourceListEmptySubtitle
        let shouldShowPlaceholder = !hasVisibleItems
        placeholderTitleLabel.superview?.isHidden = !shouldShowPlaceholder
        outlineView.enclosingScrollView?.isHidden = shouldShowPlaceholder
    }

    private func updateDocumentSummary() {
        guard let rootNode = allOutlineItems.first, let subtitle = rootNode.subtitle, subtitle.isEmpty == false else {
            documentSummaryLabel.stringValue = ""
            documentSummaryLabel.isHidden = true
            return
        }

        documentSummaryLabel.stringValue = subtitle
        documentSummaryLabel.toolTip = rootNode.title
        documentSummaryLabel.isHidden = false
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: "NodeContextMenu")
        let copyItem = NSMenuItem(title: L10n.menuCopyNodeInfo, action: #selector(copyNodeInfoFromContextMenu(_:)), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let exportItem = NSMenuItem(title: L10n.menuExportNodeInfo, action: #selector(exportNodeInfoFromContextMenu(_:)), keyEquivalent: "")
        exportItem.target = self
        menu.addItem(exportItem)
        return menu
    }

    private func prepareContextMenu(forRow row: Int) {
        let hasSelection = row >= 0 && outlineView.item(atRow: row) as? BrowserNode != nil
        contextMenu.items.forEach { $0.isEnabled = hasSelection }
    }

    @objc private func copyNodeInfoFromContextMenu(_ sender: Any?) {
        copySelectedNodeInfo?()
    }

    @objc private func exportNodeInfoFromContextMenu(_ sender: Any?) {
        exportSelectedNodeInfo?()
    }
}

private final class BrowserOutlineRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.45 : 0.18).setFill()
            dirtyRect.fill()
            return
        }
        super.drawSelection(in: dirtyRect)
    }
}

private final class BrowserOutlineView: NSOutlineView {
    var onPrepareContextMenu: ((Int) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        if row >= 0 {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        onPrepareContextMenu?(row)
        return super.menu(for: event)
    }
}

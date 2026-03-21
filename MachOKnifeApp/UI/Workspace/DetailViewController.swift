import AppKit
import Combine
import MachOKnifeKit

@MainActor
final class DetailViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum DisplayMode: Int {
        case detail
        case data
    }

    var promptForDocument: (() -> Void)?
    var openDocument: ((URL) -> Void)?

    private let viewModel: WorkspaceViewModel
    private let emptyStateTitleLabel = NSTextField(labelWithString: L10n.workspaceEmptyTitle)
    private let emptyStateSubtitleLabel = NSTextField(labelWithString: L10n.workspaceEmptySubtitle)
    private let openButton = NSButton(title: L10n.workspaceEmptyOpenButton, target: nil, action: nil)
    private let addressModeSelector = NSSegmentedControl(
        labels: [L10n.workspaceAddressRaw, L10n.workspaceAddressRVA],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let displayModeSelector = NSSegmentedControl(
        labels: [L10n.workspaceDetailsTab, L10n.workspaceHexTab],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let previousHexButton = NSButton(title: "", target: nil, action: nil)
    private let nextHexButton = NSButton(title: "", target: nil, action: nil)
    private let hexPageLabel = NSTextField(labelWithString: "")
    private let hexNavigationControls = NSStackView()
    private let detailTableView = BrowserContextMenuTableView()
    private let detailTableScrollView = NSScrollView()
    private let detailEmptyLabel = NSTextField(wrappingLabelWithString: "")
    private let dataTableView = BrowserContextMenuTableView()
    private let dataTableScrollView = NSScrollView()
    private let dataEmptyLabel = NSTextField(wrappingLabelWithString: "")
    private let contentContainer = NSView()
    private let detailContainer = NSView()
    private let dataContainer = NSView()
    private lazy var detailContextMenu = makeDetailContextMenu()
    private lazy var dataContextMenu = makeDataContextMenu()
    private var browserDocument: BrowserDocument?
    private var detailNode: BrowserNode?
    private var hexDataSource: HexTableDataSource?
    private var hexEmptyMessage = ""
    private var cancellables = Set<AnyCancellable>()
    private var displayMode: DisplayMode = .detail {
        didSet {
            updateDisplayedPane()
        }
    }

    init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let dropView = WorkspaceDropView(backgroundColor: .windowBackgroundColor)
        dropView.onFileURLDropped = { [weak self] url in
            self?.openDocument?(url)
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

    @objc private func addressModeChanged(_ sender: NSSegmentedControl) {
        let mode: WorkspaceViewModel.BrowserAddressMode = sender.selectedSegment == 1 ? .rva : .raw
        viewModel.setBrowserAddressMode(mode)
    }

    @objc private func displayModeChanged(_ sender: NSSegmentedControl) {
        displayMode = sender.selectedSegment == DisplayMode.data.rawValue ? .data : .detail
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == detailTableView {
            return detailNode?.detailCount ?? 0
        }
        return hexDataSource?.rowCount ?? 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }

        if tableView == detailTableView {
            guard let detailNode, row >= 0, row < detailNode.detailCount else { return nil }
            return detailCell(for: tableColumn, row: detailNode.detailRow(at: row))
        }

        guard let row = hexDataSource?.row(at: row) else { return nil }
        return hexCell(for: tableColumn, row: row)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard tableView == detailTableView else {
            return BrowserDetailTableRowView()
        }

        let rowView = BrowserDetailTableRowView()
        if let detailNode, row >= 0, row < detailNode.detailCount {
            let currentGroup = detailNode.detailRow(at: row).groupIdentifier
            let previousGroup = row > 0 ? detailNode.detailRow(at: row - 1).groupIdentifier : currentGroup
            rowView.drawTopSeparator = row > 0 && currentGroup != previousGroup
        }
        return rowView
    }

    func reloadLocalization() {
        emptyStateTitleLabel.stringValue = L10n.workspaceEmptyTitle
        emptyStateSubtitleLabel.stringValue = L10n.workspaceEmptySubtitle
        openButton.title = L10n.workspaceEmptyOpenButton
        addressModeSelector.setLabel(L10n.workspaceAddressRaw, forSegment: 0)
        addressModeSelector.setLabel(L10n.workspaceAddressRVA, forSegment: 1)
        displayModeSelector.setLabel(L10n.workspaceDetailsTab, forSegment: 0)
        displayModeSelector.setLabel(L10n.workspaceHexTab, forSegment: 1)
        detailEmptyLabel.stringValue = L10n.workspaceDetailEmpty
        dataEmptyLabel.stringValue = hexEmptyMessage.isEmpty ? L10n.workspaceDataEmpty : hexEmptyMessage
        refreshColumnTitles()
        reloadContextMenuLocalization()
        refreshSelection(viewModel.browserSelectedNode)
        refreshHexPresentation(document: browserDocument, node: viewModel.browserSelectedNode)
    }

    private func buildUI() {
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
        emptyStack.identifier = NSUserInterfaceItemIdentifier("workspace.empty.stack")

        addressModeSelector.selectedSegment = 0
        addressModeSelector.target = self
        addressModeSelector.action = #selector(addressModeChanged(_:))
        addressModeSelector.translatesAutoresizingMaskIntoConstraints = false

        displayModeSelector.selectedSegment = 0
        displayModeSelector.target = self
        displayModeSelector.action = #selector(displayModeChanged(_:))
        displayModeSelector.translatesAutoresizingMaskIntoConstraints = false

        hexNavigationControls.orientation = .horizontal
        hexNavigationControls.alignment = .centerY
        hexNavigationControls.spacing = 8
        hexNavigationControls.translatesAutoresizingMaskIntoConstraints = false
        hexNavigationControls.isHidden = true

        let topControls = NSStackView(views: [addressModeSelector, displayModeSelector, NSView(), hexNavigationControls])
        topControls.orientation = .horizontal
        topControls.alignment = .centerY
        topControls.spacing = 8
        topControls.translatesAutoresizingMaskIntoConstraints = false

        configureDetailTable()
        configureDataTable()

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.isHidden = true
        contentContainer.addSubview(topControls)
        contentContainer.addSubview(detailContainer)
        contentContainer.addSubview(dataContainer)

        view.addSubview(emptyStack)
        view.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            emptyStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            contentContainer.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),

            topControls.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            topControls.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            topControls.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),

            detailContainer.topAnchor.constraint(equalTo: topControls.bottomAnchor, constant: 12),
            detailContainer.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            dataContainer.topAnchor.constraint(equalTo: topControls.bottomAnchor, constant: 12),
            dataContainer.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            dataContainer.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            dataContainer.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        updateDisplayedPane()
        reloadLocalization()
    }

    private func configureDetailTable() {
        let addressColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("address"))
        addressColumn.width = 96
        let dataColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("data"))
        dataColumn.width = 164
        let detailColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        detailColumn.width = 220
        let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        valueColumn.width = 360

        detailTableView.addTableColumn(addressColumn)
        detailTableView.addTableColumn(dataColumn)
        detailTableView.addTableColumn(detailColumn)
        detailTableView.addTableColumn(valueColumn)
        detailTableView.headerView = NSTableHeaderView()
        detailTableView.rowHeight = 22
        detailTableView.usesAlternatingRowBackgroundColors = false
        detailTableView.delegate = self
        detailTableView.dataSource = self
        detailTableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        detailTableView.menu = detailContextMenu
        detailTableView.onPrepareContextMenu = { [weak self] row in
            self?.prepareDetailContextMenu(forRow: row)
        }

        detailTableScrollView.translatesAutoresizingMaskIntoConstraints = false
        detailTableScrollView.drawsBackground = false
        detailTableScrollView.hasVerticalScroller = true
        detailTableScrollView.documentView = detailTableView

        detailEmptyLabel.textColor = .tertiaryLabelColor
        detailEmptyLabel.alignment = .center
        detailEmptyLabel.maximumNumberOfLines = 0
        detailEmptyLabel.translatesAutoresizingMaskIntoConstraints = false

        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(detailTableScrollView)
        detailContainer.addSubview(detailEmptyLabel)

        NSLayoutConstraint.activate([
            detailTableScrollView.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            detailTableScrollView.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailTableScrollView.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailTableScrollView.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),

            detailEmptyLabel.centerXAnchor.constraint(equalTo: detailContainer.centerXAnchor),
            detailEmptyLabel.centerYAnchor.constraint(equalTo: detailContainer.centerYAnchor),
            detailEmptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: detailContainer.leadingAnchor, constant: 24),
            detailEmptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: detailContainer.trailingAnchor, constant: -24),
        ])
    }

    private func configureDataTable() {
        let addressColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("address"))
        addressColumn.width = 96
        let lowColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("low"))
        lowColumn.width = 210
        let highColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("high"))
        highColumn.width = 210
        let asciiColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ascii"))
        asciiColumn.width = 170

        dataTableView.addTableColumn(addressColumn)
        dataTableView.addTableColumn(lowColumn)
        dataTableView.addTableColumn(highColumn)
        dataTableView.addTableColumn(asciiColumn)
        dataTableView.headerView = NSTableHeaderView()
        dataTableView.rowHeight = 24
        dataTableView.usesAlternatingRowBackgroundColors = false
        dataTableView.delegate = self
        dataTableView.dataSource = self
        dataTableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        dataTableView.menu = dataContextMenu
        dataTableView.onPrepareContextMenu = { [weak self] row in
            self?.prepareDataContextMenu(forRow: row)
        }

        dataTableScrollView.translatesAutoresizingMaskIntoConstraints = false
        dataTableScrollView.drawsBackground = false
        dataTableScrollView.hasVerticalScroller = true
        dataTableScrollView.documentView = dataTableView

        dataEmptyLabel.textColor = .tertiaryLabelColor
        dataEmptyLabel.alignment = .center
        dataEmptyLabel.maximumNumberOfLines = 0
        dataEmptyLabel.translatesAutoresizingMaskIntoConstraints = false

        dataContainer.translatesAutoresizingMaskIntoConstraints = false
        dataContainer.addSubview(dataTableScrollView)
        dataContainer.addSubview(dataEmptyLabel)

        NSLayoutConstraint.activate([
            dataTableScrollView.topAnchor.constraint(equalTo: dataContainer.topAnchor),
            dataTableScrollView.leadingAnchor.constraint(equalTo: dataContainer.leadingAnchor),
            dataTableScrollView.trailingAnchor.constraint(equalTo: dataContainer.trailingAnchor),
            dataTableScrollView.bottomAnchor.constraint(equalTo: dataContainer.bottomAnchor),

            dataEmptyLabel.centerXAnchor.constraint(equalTo: dataContainer.centerXAnchor),
            dataEmptyLabel.centerYAnchor.constraint(equalTo: dataContainer.centerYAnchor),
            dataEmptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: dataContainer.leadingAnchor, constant: 24),
            dataEmptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: dataContainer.trailingAnchor, constant: -24),
        ])
    }

    private func bindViewModel() {
        Publishers.CombineLatest3(
            viewModel.$browserDocument,
            viewModel.$browserSelectedNode,
            viewModel.$errorMessage
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] browserDocument, selectedNode, errorMessage in
            guard let self else { return }
            self.browserDocument = browserDocument
            let showContent = browserDocument != nil || errorMessage != nil
            contentContainer.isHidden = !showContent
            emptyStateTitleLabel.superview?.isHidden = showContent

            if let errorMessage {
                self.browserDocument = nil
                detailNode = nil
                hexDataSource = nil
                hexEmptyMessage = errorMessage
                detailEmptyLabel.stringValue = errorMessage
                dataEmptyLabel.stringValue = errorMessage
                detailTableView.reloadData()
                dataTableView.reloadData()
            } else {
                detailEmptyLabel.stringValue = L10n.workspaceDetailEmpty
                refreshSelection(selectedNode)
                refreshHexPresentation(document: browserDocument, node: selectedNode)
            }
        }
        .store(in: &cancellables)

        viewModel.$browserAddressMode
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                self?.addressModeSelector.selectedSegment = mode == .raw ? 0 : 1
                self?.refreshColumnTitles()
                self?.detailTableView.reloadData()
                self?.refreshHexPresentation(document: self?.browserDocument, node: self?.viewModel.browserSelectedNode)
            }
            .store(in: &cancellables)
    }

    private func detailCell(for tableColumn: NSTableColumn, row: BrowserDetailRow) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("BrowserDetailCell.\(tableColumn.identifier.rawValue)")
        let cell = detailTableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        if cell.textField == nil {
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.maximumNumberOfLines = 1
            textField.usesSingleLineMode = true
            textField.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            cell.textField = textField
        }

        switch tableColumn.identifier.rawValue {
        case "address":
            cell.textField?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.textField?.stringValue = addressString(for: row)
            cell.textField?.textColor = .secondaryLabelColor
        case "data":
            cell.textField?.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            cell.textField?.stringValue = row.dataPreview ?? ""
            cell.textField?.textColor = .secondaryLabelColor
        case "name":
            cell.textField?.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            cell.textField?.stringValue = row.key
            cell.textField?.textColor = .labelColor
        default:
            cell.textField?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.textField?.stringValue = row.value
            cell.textField?.textColor = .secondaryLabelColor
        }

        return cell
    }

    private func hexCell(for tableColumn: NSTableColumn, row: BrowserHexRow) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("BrowserHexCell.\(tableColumn.identifier.rawValue)")
        let cell = dataTableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        if cell.textField == nil {
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.maximumNumberOfLines = 1
            textField.usesSingleLineMode = true
            textField.lineBreakMode = .byClipping
            textField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            cell.textField = textField
        }

        switch tableColumn.identifier.rawValue {
        case "address":
            cell.textField?.stringValue = row.address
            cell.textField?.textColor = .secondaryLabelColor
        case "low":
            cell.textField?.stringValue = row.lowBytes
            cell.textField?.textColor = .labelColor
        case "high":
            cell.textField?.stringValue = row.highBytes
            cell.textField?.textColor = .labelColor
        default:
            cell.textField?.stringValue = row.ascii
            cell.textField?.textColor = .secondaryLabelColor
        }

        return cell
    }

    private func refreshSelection(_ node: BrowserNode?) {
        detailNode = node
        detailTableView.reloadData()
        detailEmptyLabel.isHidden = (detailNode?.detailCount ?? 0) > 0
    }

    private func refreshHexPresentation(document: BrowserDocument?, node: BrowserNode?) {
        guard let document else {
            hexDataSource = nil
            hexEmptyMessage = L10n.workspaceDataEmpty
            dataTableView.reloadData()
            dataEmptyLabel.stringValue = hexEmptyMessage
            dataEmptyLabel.isHidden = false
            return
        }

        switch document.hexSource {
        case let .unavailable(reason):
            hexDataSource = nil
            hexEmptyMessage = reason
        case let .file(url, size):
            if let node, let dataRange = node.dataRange {
                let clampedOffset = max(0, min(dataRange.offset, max(size - 1, 0)))
                let remaining = max(0, size - clampedOffset)
                let clampedLength = min(dataRange.length, remaining)
                guard clampedLength > 0 else {
                    hexDataSource = nil
                    hexEmptyMessage = L10n.workspaceHexUnavailable
                    dataTableView.reloadData()
                    dataEmptyLabel.stringValue = hexEmptyMessage
                    dataEmptyLabel.isHidden = false
                    return
                }

                let baseAddress = switch viewModel.browserAddressMode {
                case .raw:
                    Int(node.rawAddress ?? UInt64(clampedOffset))
                case .rva:
                    Int(node.rvaAddress ?? UInt64(clampedOffset))
                }
                hexDataSource = HexTableDataSource(
                    url: url,
                    offset: clampedOffset,
                    length: clampedLength,
                    baseAddress: baseAddress
                )
                hexEmptyMessage = ""
            } else {
                hexDataSource = HexTableDataSource(
                    url: url,
                    offset: 0,
                    length: size,
                    baseAddress: 0
                )
                hexEmptyMessage = size > 0 ? "" : L10n.workspaceDataEmpty
            }
        }

        dataTableView.reloadData()
        let hasRows = (hexDataSource?.rowCount ?? 0) > 0
        dataEmptyLabel.stringValue = hasRows ? "" : (hexEmptyMessage.isEmpty ? L10n.workspaceDataEmpty : hexEmptyMessage)
        dataEmptyLabel.isHidden = hasRows
    }

    private func refreshColumnTitles() {
        let addressTitle = L10n.workspaceDetailColumnAddress

        detailTableView.tableColumns.first { $0.identifier.rawValue == "address" }?.title = addressTitle
        detailTableView.tableColumns.first { $0.identifier.rawValue == "data" }?.title = L10n.workspaceDetailColumnData
        detailTableView.tableColumns.first { $0.identifier.rawValue == "name" }?.title = L10n.workspaceDetailColumnName
        detailTableView.tableColumns.first { $0.identifier.rawValue == "value" }?.title = L10n.workspaceDetailColumnValue

        dataTableView.tableColumns.first { $0.identifier.rawValue == "address" }?.title = addressTitle
        dataTableView.tableColumns.first { $0.identifier.rawValue == "low" }?.title = "Data LO"
        dataTableView.tableColumns.first { $0.identifier.rawValue == "high" }?.title = "DATA HI"
        dataTableView.tableColumns.first { $0.identifier.rawValue == "ascii" }?.title = L10n.workspaceDetailColumnValue
    }

    private func updateDisplayedPane() {
        detailContainer.isHidden = displayMode != .detail
        dataContainer.isHidden = displayMode != .data
        hexNavigationControls.isHidden = true
        displayModeSelector.selectedSegment = displayMode.rawValue
    }

    private func makeDetailContextMenu() -> NSMenu {
        let menu = NSMenu(title: "DetailRowContextMenu")
        menu.addItem(NSMenuItem(title: L10n.workspaceContextCopyRow, action: #selector(copyDetailRowInfo(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L10n.workspaceContextCopyAddress, action: #selector(copyDetailRowAddress(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.workspaceContextCopyBinaryValue, action: #selector(copyDetailRowBinaryValue(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.workspaceContextCopyDescription, action: #selector(copyDetailRowDescription(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.workspaceContextCopyValue, action: #selector(copyDetailRowValue(_:)), keyEquivalent: ""))
        menu.items.forEach { $0.target = self }
        return menu
    }

    private func makeDataContextMenu() -> NSMenu {
        let menu = NSMenu(title: "HexRowContextMenu")
        menu.addItem(NSMenuItem(title: L10n.workspaceContextCopyRow, action: #selector(copyDataRowInfo(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L10n.workspaceContextCopyAddress, action: #selector(copyDataRowAddress(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.workspaceContextCopyBinaryValue, action: #selector(copyDataRowBinaryValue(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.workspaceContextCopyLowBytes, action: #selector(copyDataRowLowBytes(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.workspaceContextCopyHighBytes, action: #selector(copyDataRowHighBytes(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.workspaceContextCopyValue, action: #selector(copyDataRowValue(_:)), keyEquivalent: ""))
        menu.items.forEach { $0.target = self }
        return menu
    }

    private func reloadContextMenuLocalization() {
        if detailContextMenu.items.count >= 6 {
            detailContextMenu.items[0].title = L10n.workspaceContextCopyRow
            detailContextMenu.items[2].title = L10n.workspaceContextCopyAddress
            detailContextMenu.items[3].title = L10n.workspaceContextCopyBinaryValue
            detailContextMenu.items[4].title = L10n.workspaceContextCopyDescription
            detailContextMenu.items[5].title = L10n.workspaceContextCopyValue
        }

        if dataContextMenu.items.count >= 7 {
            dataContextMenu.items[0].title = L10n.workspaceContextCopyRow
            dataContextMenu.items[2].title = L10n.workspaceContextCopyAddress
            dataContextMenu.items[3].title = L10n.workspaceContextCopyBinaryValue
            dataContextMenu.items[4].title = L10n.workspaceContextCopyLowBytes
            dataContextMenu.items[5].title = L10n.workspaceContextCopyHighBytes
            dataContextMenu.items[6].title = L10n.workspaceContextCopyValue
        }
    }

    private func prepareDetailContextMenu(forRow row: Int) {
        let selectedRow = row >= 0 ? row : detailTableView.selectedRow
        let detailRow = detailRow(at: selectedRow)
        let hasSelection = detailRow != nil
        detailContextMenu.items[0].isEnabled = hasSelection
        detailContextMenu.items[2].isEnabled = detailRow.flatMap { detailAddressString(for: $0) }.isNonEmpty
        detailContextMenu.items[3].isEnabled = detailRow?.dataPreview?.isNonEmpty == true
        detailContextMenu.items[4].isEnabled = detailRow?.key.isNonEmpty == true
        detailContextMenu.items[5].isEnabled = detailRow?.value.isNonEmpty == true
    }

    private func prepareDataContextMenu(forRow row: Int) {
        let selectedRow = row >= 0 ? row : dataTableView.selectedRow
        let hexRow = hexRow(at: selectedRow)
        let hasSelection = hexRow != nil
        dataContextMenu.items[0].isEnabled = hasSelection
        dataContextMenu.items[2].isEnabled = hexRow?.address.isNonEmpty == true
        dataContextMenu.items[3].isEnabled = hexBinaryValue(for: hexRow).isNonEmpty
        dataContextMenu.items[4].isEnabled = hexRow?.lowBytes.trimmingCharacters(in: .whitespaces).isEmpty == false
        dataContextMenu.items[5].isEnabled = hexRow?.highBytes.trimmingCharacters(in: .whitespaces).isEmpty == false
        dataContextMenu.items[6].isEnabled = hexRow?.ascii.isNonEmpty == true
    }

    private func detailRow(at row: Int) -> BrowserDetailRow? {
        guard let detailNode, row >= 0, row < detailNode.detailCount else { return nil }
        return detailNode.detailRow(at: row)
    }

    private func hexRow(at row: Int) -> BrowserHexRow? {
        guard row >= 0 else { return nil }
        return hexDataSource?.row(at: row)
    }

    private func copyToPasteboard(_ value: String) {
        guard value.isEmpty == false else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func detailAddressString(for row: BrowserDetailRow) -> String {
        addressString(for: row)
    }

    private func formattedDetailRowInfo(_ row: BrowserDetailRow) -> String {
        [
            "\(L10n.workspaceDetailColumnAddress): \(detailAddressString(for: row))",
            "\(L10n.workspaceDetailColumnData): \(row.dataPreview ?? "")",
            "\(L10n.workspaceDetailColumnName): \(row.key)",
            "\(L10n.workspaceDetailColumnValue): \(row.value)",
        ].joined(separator: "\n")
    }

    private func formattedHexRowInfo(_ row: BrowserHexRow) -> String {
        [
            "\(L10n.workspaceDetailColumnAddress): \(row.address)",
            "Data LO: \(row.lowBytes.trimmingCharacters(in: .whitespaces))",
            "DATA HI: \(row.highBytes.trimmingCharacters(in: .whitespaces))",
            "\(L10n.workspaceDetailColumnValue): \(row.ascii)",
        ].joined(separator: "\n")
    }

    private func hexBinaryValue(for row: BrowserHexRow?) -> String {
        guard let row else { return "" }
        let parts = [
            row.lowBytes.trimmingCharacters(in: .whitespaces),
            row.highBytes.trimmingCharacters(in: .whitespaces),
        ].filter { $0.isEmpty == false }
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    @objc private func copyDetailRowInfo(_ sender: Any?) {
        guard let row = detailRow(at: detailTableView.selectedRow) else { return }
        copyToPasteboard(formattedDetailRowInfo(row))
    }

    @objc private func copyDetailRowAddress(_ sender: Any?) {
        guard let row = detailRow(at: detailTableView.selectedRow) else { return }
        copyToPasteboard(detailAddressString(for: row))
    }

    @objc private func copyDetailRowBinaryValue(_ sender: Any?) {
        guard let row = detailRow(at: detailTableView.selectedRow) else { return }
        copyToPasteboard(row.dataPreview ?? "")
    }

    @objc private func copyDetailRowDescription(_ sender: Any?) {
        guard let row = detailRow(at: detailTableView.selectedRow) else { return }
        copyToPasteboard(row.key)
    }

    @objc private func copyDetailRowValue(_ sender: Any?) {
        guard let row = detailRow(at: detailTableView.selectedRow) else { return }
        copyToPasteboard(row.value)
    }

    @objc private func copyDataRowInfo(_ sender: Any?) {
        guard let row = hexRow(at: dataTableView.selectedRow) else { return }
        copyToPasteboard(formattedHexRowInfo(row))
    }

    @objc private func copyDataRowAddress(_ sender: Any?) {
        guard let row = hexRow(at: dataTableView.selectedRow) else { return }
        copyToPasteboard(row.address)
    }

    @objc private func copyDataRowBinaryValue(_ sender: Any?) {
        copyToPasteboard(hexBinaryValue(for: hexRow(at: dataTableView.selectedRow)))
    }

    @objc private func copyDataRowLowBytes(_ sender: Any?) {
        guard let row = hexRow(at: dataTableView.selectedRow) else { return }
        copyToPasteboard(row.lowBytes.trimmingCharacters(in: .whitespaces))
    }

    @objc private func copyDataRowHighBytes(_ sender: Any?) {
        guard let row = hexRow(at: dataTableView.selectedRow) else { return }
        copyToPasteboard(row.highBytes.trimmingCharacters(in: .whitespaces))
    }

    @objc private func copyDataRowValue(_ sender: Any?) {
        guard let row = hexRow(at: dataTableView.selectedRow) else { return }
        copyToPasteboard(row.ascii)
    }

    private func addressString(for row: BrowserDetailRow) -> String {
        let value = switch viewModel.browserAddressMode {
        case .raw:
            row.rawAddress
        case .rva:
            row.rvaAddress
        }

        guard let value else { return "" }
        return String(format: "%08llX", value)
    }
}

private final class HexTableDataSource {
    private static let bytesPerLine = 16
    private static let chunkByteCount = 16 * 256

    let rowCount: Int

    private let url: URL
    private let offset: Int
    private let length: Int
    private let baseAddress: Int
    private var chunkCache: [Int: Data] = [:]

    init(url: URL, offset: Int, length: Int, baseAddress: Int) {
        self.url = url
        self.offset = offset
        self.length = max(0, length)
        self.baseAddress = baseAddress
        self.rowCount = self.length == 0 ? 0 : Int(ceil(Double(self.length) / Double(Self.bytesPerLine)))
    }

    func row(at index: Int) -> BrowserHexRow? {
        guard index >= 0, index < rowCount else { return nil }

        let lineOffset = index * Self.bytesPerLine
        let chunkIndex = lineOffset / Self.chunkByteCount
        let chunkStart = chunkIndex * Self.chunkByteCount
        let rowStart = lineOffset - chunkStart
        guard let chunk = chunk(at: chunkIndex) else { return nil }
        guard rowStart < chunk.count else { return nil }

        let bytes = Array(chunk[rowStart..<min(rowStart + Self.bytesPerLine, chunk.count)])
        let hexBytes = bytes.map { String(format: "%02X", $0) }
        let low = hexBytes.prefix(8).joined(separator: " ").padding(toLength: 24, withPad: " ", startingAt: 0)
        let high = Array(hexBytes.dropFirst(8)).joined(separator: " ").padding(toLength: 24, withPad: " ", startingAt: 0)
        let ascii = bytes.map { byte -> Character in
            if byte >= 0x20 && byte <= 0x7E {
                return Character(UnicodeScalar(byte))
            }
            return "."
        }

        return BrowserHexRow(
            address: String(format: "%08X", baseAddress + lineOffset),
            lowBytes: low,
            highBytes: high,
            ascii: String(ascii)
        )
    }

    private func chunk(at index: Int) -> Data? {
        if let cached = chunkCache[index] {
            return cached
        }

        let chunkStart = index * Self.chunkByteCount
        guard chunkStart < length else {
            return nil
        }

        let bytesToRead = min(Self.chunkByteCount, length - chunkStart)
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            return nil
        }
        defer {
            try? handle.close()
        }

        do {
            try handle.seek(toOffset: UInt64(offset + chunkStart))
            let data = handle.readData(ofLength: bytesToRead)
            chunkCache[index] = data
            return data
        } catch {
            return nil
        }
    }
}

private final class BrowserDetailTableRowView: NSTableRowView {
    var drawTopSeparator = false

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)

        guard drawTopSeparator else { return }
        NSColor.separatorColor.setStroke()
        NSBezierPath.strokeLine(
            from: NSPoint(x: bounds.minX, y: bounds.minY),
            to: NSPoint(x: bounds.maxX, y: bounds.minY)
        )
    }
}

private final class BrowserContextMenuTableView: NSTableView {
    var onPrepareContextMenu: ((Int) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        if row >= 0 {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            deselectAll(nil)
        }
        onPrepareContextMenu?(row)
        return super.menu(for: event)
    }
}

private extension Optional where Wrapped == String {
    var isNonEmpty: Bool {
        self?.isNonEmpty == true
    }
}

private extension String {
    var isNonEmpty: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

private final class WorkspaceDropView: AdaptiveBackgroundView {
    var onFileURLDropped: ((URL) -> Void)?

    override init(backgroundColor: NSColor) {
        super.init(backgroundColor: backgroundColor)
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

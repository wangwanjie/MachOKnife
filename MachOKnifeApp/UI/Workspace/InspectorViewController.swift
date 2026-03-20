import AppKit
import Combine
import CoreMachO
import MachOKnifeKit

@MainActor
final class InspectorViewController: NSViewController {
    private enum Tab: Int {
        case overview
        case dylibs
        case rpaths
        case platform
        case preview
    }

    private let supportedPlatforms: [MachOPlatform] = [
        .macOS,
        .iOS,
        .tvOS,
        .watchOS,
        .bridgeOS,
        .macCatalyst,
        .iOSSimulator,
        .visionOS,
        .tvOSSimulator,
        .watchOSSimulator,
        .driverKit,
        .visionOSSimulator,
        .firmware,
        .sepOS,
    ]

    private let viewModel: WorkspaceViewModel
    private let tabView = NSTabView()
    private let overviewSummaryLabel = NSTextField(wrappingLabelWithString: "")
    private let installNameField = NSTextField(string: "")
    private let dylibEmptyLabel = NSTextField(wrappingLabelWithString: "")
    private let dylibStackView = NSStackView()
    private let rpathEmptyLabel = NSTextField(wrappingLabelWithString: "")
    private let rpathStackView = NSStackView()
    private let addRPathButton = NSButton(title: "", target: nil, action: nil)
    private let platformPopupButton = NSPopUpButton()
    private let minimumOSTextField = NSTextField(string: "")
    private let sdkTextField = NSTextField(string: "")
    private let platformHintLabel = NSTextField(wrappingLabelWithString: "")
    private let previewButton = NSButton(title: "", target: nil, action: nil)
    private let previewTextView = NSTextView()
    private var cancellables = Set<AnyCancellable>()
    private var isUpdatingControls = false

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

    func selectPreviewTab() {
        tabView.selectTabViewItem(at: Tab.preview.rawValue)
    }

    private func buildUI() {
        let titleLabel = NSTextField(labelWithString: L10n.inspectorTitle)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.tabViewType = .topTabsBezelBorder
        tabView.addTabViewItem(makeTab(label: L10n.inspectorTabOverview, view: makeOverviewTab()))
        tabView.addTabViewItem(makeTab(label: L10n.inspectorTabDylibs, view: makeDylibsTab()))
        tabView.addTabViewItem(makeTab(label: L10n.inspectorTabRPaths, view: makeRPathsTab()))
        tabView.addTabViewItem(makeTab(label: L10n.inspectorTabPlatform, view: makePlatformTab()))
        tabView.addTabViewItem(makeTab(label: L10n.inspectorTabPreview, view: makePreviewTab()))

        view.addSubview(titleLabel)
        view.addSubview(tabView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            tabView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            tabView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tabView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    private func makeOverviewTab() -> NSView {
        overviewSummaryLabel.textColor = .secondaryLabelColor

        let installNameLabel = makeFieldLabel(L10n.inspectorInstallNameLabel)
        installNameField.placeholderString = "@rpath/libMachOKnife.dylib"
        installNameField.target = self
        installNameField.action = #selector(installNameDidChange(_:))

        let stackView = NSStackView(views: [overviewSummaryLabel, installNameLabel, installNameField])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        return wrappedContentView(for: stackView)
    }

    private func makeDylibsTab() -> NSView {
        dylibEmptyLabel.textColor = .secondaryLabelColor
        dylibEmptyLabel.stringValue = L10n.inspectorDylibsEmpty

        dylibStackView.orientation = .vertical
        dylibStackView.alignment = .leading
        dylibStackView.spacing = 10

        let content = NSStackView(views: [dylibEmptyLabel, dylibStackView])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        return wrappedScrollingView(for: content)
    }

    private func makeRPathsTab() -> NSView {
        addRPathButton.title = L10n.inspectorAddRPath
        addRPathButton.bezelStyle = .rounded
        addRPathButton.target = self
        addRPathButton.action = #selector(addRPath(_:))

        rpathEmptyLabel.textColor = .secondaryLabelColor
        rpathEmptyLabel.stringValue = L10n.inspectorRPathsEmpty

        rpathStackView.orientation = .vertical
        rpathStackView.alignment = .leading
        rpathStackView.spacing = 10

        let content = NSStackView(views: [addRPathButton, rpathEmptyLabel, rpathStackView])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        return wrappedScrollingView(for: content)
    }

    private func makePlatformTab() -> NSView {
        supportedPlatforms.forEach { platform in
            platformPopupButton.addItem(withTitle: title(for: platform))
        }
        platformPopupButton.target = self
        platformPopupButton.action = #selector(platformControlDidChange(_:))

        minimumOSTextField.placeholderString = "17.0.0"
        minimumOSTextField.target = self
        minimumOSTextField.action = #selector(platformControlDidChange(_:))

        sdkTextField.placeholderString = "17.4.0"
        sdkTextField.target = self
        sdkTextField.action = #selector(platformControlDidChange(_:))

        platformHintLabel.stringValue = L10n.inspectorPlatformHint
        platformHintLabel.textColor = .secondaryLabelColor

        let stackView = NSStackView(views: [
            makeFieldLabel(L10n.inspectorPlatformLabel),
            platformPopupButton,
            makeFieldLabel(L10n.inspectorMinimumOSLabel),
            minimumOSTextField,
            makeFieldLabel(L10n.inspectorSDKLabel),
            sdkTextField,
            platformHintLabel,
        ])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        return wrappedContentView(for: stackView)
    }

    private func makePreviewTab() -> NSView {
        previewButton.title = L10n.inspectorPreviewAction
        previewButton.bezelStyle = .rounded
        previewButton.target = self
        previewButton.action = #selector(previewEdits(_:))

        previewTextView.isEditable = false
        previewTextView.isSelectable = true
        previewTextView.drawsBackground = false
        previewTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        previewTextView.string = L10n.inspectorPreviewPlaceholder

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = previewTextView

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(previewButton)
        container.addSubview(scrollView)

        previewButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            previewButton.topAnchor.constraint(equalTo: container.topAnchor),
            previewButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            scrollView.topAnchor.constraint(equalTo: previewButton.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func bindViewModel() {
        Publishers.CombineLatest(viewModel.$editableSlice, viewModel.$selectedSliceSummary)
            .receive(on: RunLoop.main)
            .sink { [weak self] editableSlice, sliceSummary in
                self?.renderDraft(editableSlice, sliceSummary: sliceSummary)
            }
            .store(in: &cancellables)

        viewModel.$previewText
            .receive(on: RunLoop.main)
            .sink { [weak self] previewText in
                self?.previewTextView.string = previewText.isEmpty ? L10n.inspectorPreviewPlaceholder : previewText
            }
            .store(in: &cancellables)
    }

    private func renderDraft(_ editableSlice: EditableSliceViewModel?, sliceSummary: SliceSummary?) {
        isUpdatingControls = true
        defer { isUpdatingControls = false }

        let hasEditableSlice = editableSlice != nil

        if let editableSlice, let sliceSummary {
            overviewSummaryLabel.stringValue = """
            Slice \(editableSlice.sliceIndex) • \(sliceSummary.is64Bit ? "64-bit" : "32-bit") • \(sliceSummary.loadCommandCount) load commands
            Platform: \(title(for: sliceSummary.platform ?? .unknown(0))) • minOS: \(sliceSummary.minimumOS?.description ?? "n/a") • SDK: \(sliceSummary.sdkVersion?.description ?? "n/a")
            """
            installNameField.stringValue = editableSlice.installName
        } else {
            overviewSummaryLabel.stringValue = L10n.inspectorPlaceholder
            installNameField.stringValue = ""
        }

        installNameField.isEnabled = hasEditableSlice
        rebuildDylibRows(using: editableSlice?.dylibReferences ?? [])
        rebuildRPathRows(using: editableSlice?.rpaths ?? [])
        addRPathButton.isEnabled = hasEditableSlice
        applyPlatformMetadata(editableSlice?.platformMetadata, enabled: hasEditableSlice)
    }

    private func rebuildDylibRows(using references: [EditableDylibReference]) {
        clearArrangedSubviews(from: dylibStackView)
        dylibEmptyLabel.isHidden = !references.isEmpty

        for (index, reference) in references.enumerated() {
            let commandLabel = NSTextField(labelWithString: commandTitle(for: reference.command))
            commandLabel.textColor = .secondaryLabelColor
            commandLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)

            let textField = NSTextField(string: reference.path)
            textField.tag = index
            textField.target = self
            textField.action = #selector(dylibPathDidChange(_:))

            let row = NSStackView(views: [commandLabel, textField])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 6
            row.translatesAutoresizingMaskIntoConstraints = false
            textField.widthAnchor.constraint(equalToConstant: 280).isActive = true
            dylibStackView.addArrangedSubview(row)
        }
    }

    private func rebuildRPathRows(using rpaths: [String]) {
        clearArrangedSubviews(from: rpathStackView)
        rpathEmptyLabel.isHidden = !rpaths.isEmpty

        for (index, path) in rpaths.enumerated() {
            let textField = NSTextField(string: path)
            textField.tag = index
            textField.target = self
            textField.action = #selector(rpathDidChange(_:))
            textField.widthAnchor.constraint(equalToConstant: 220).isActive = true

            let removeButton = NSButton(title: L10n.inspectorRemoveAction, target: self, action: #selector(removeRPath(_:)))
            removeButton.tag = index
            removeButton.bezelStyle = .rounded

            let row = NSStackView(views: [textField, removeButton])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            rpathStackView.addArrangedSubview(row)
        }
    }

    private func applyPlatformMetadata(_ metadata: EditablePlatformMetadata?, enabled: Bool) {
        let hasMetadata = metadata != nil
        platformPopupButton.isEnabled = enabled && hasMetadata
        minimumOSTextField.isEnabled = enabled && hasMetadata
        sdkTextField.isEnabled = enabled && hasMetadata

        guard let metadata else {
            platformPopupButton.selectItem(at: 0)
            minimumOSTextField.stringValue = ""
            sdkTextField.stringValue = ""
            platformHintLabel.stringValue = enabled ? L10n.inspectorPlatformUnavailable : L10n.inspectorPlatformHint
            platformHintLabel.textColor = .secondaryLabelColor
            return
        }

        if let index = supportedPlatforms.firstIndex(of: metadata.platform) {
            platformPopupButton.selectItem(at: index)
        } else {
            platformPopupButton.selectItem(at: 0)
        }

        minimumOSTextField.stringValue = metadata.minimumOS.description
        sdkTextField.stringValue = metadata.sdk.description
        platformHintLabel.stringValue = L10n.inspectorPlatformHint
        platformHintLabel.textColor = .secondaryLabelColor
    }

    @objc private func installNameDidChange(_ sender: NSTextField) {
        guard !isUpdatingControls else { return }
        viewModel.setInstallNameDraft(sender.stringValue)
    }

    @objc private func dylibPathDidChange(_ sender: NSTextField) {
        guard !isUpdatingControls, let editableSlice = viewModel.editableSlice else { return }
        guard editableSlice.dylibReferences.indices.contains(sender.tag) else { return }

        viewModel.setDylibPathDraft(at: sender.tag, newPath: sender.stringValue)
    }

    @objc private func addRPath(_ sender: Any?) {
        viewModel.addRPathDraft("")
    }

    @objc private func rpathDidChange(_ sender: NSTextField) {
        guard !isUpdatingControls else { return }
        viewModel.updateRPathDraft(at: sender.tag, path: sender.stringValue)
    }

    @objc private func removeRPath(_ sender: NSButton) {
        viewModel.removeRPathDraft(at: sender.tag)
    }

    @objc private func platformControlDidChange(_ sender: Any?) {
        guard !isUpdatingControls else { return }
        applyPlatformDraftFromControls()
    }

    @objc private func previewEdits(_ sender: Any?) {
        do {
            try viewModel.previewEdits()
            selectPreviewTab()
        } catch {
            presentOperationError(error)
        }
    }

    private func applyPlatformDraftFromControls() {
        guard let selectedItem = platformPopupButton.selectedItem else { return }
        guard let platform = platform(for: selectedItem.title) else { return }

        guard
            let minimumOS = parseVersion(from: minimumOSTextField.stringValue),
            let sdk = parseVersion(from: sdkTextField.stringValue)
        else {
            platformHintLabel.stringValue = L10n.inspectorPlatformInvalidVersion
            platformHintLabel.textColor = .systemRed
            return
        }

        platformHintLabel.stringValue = L10n.inspectorPlatformHint
        platformHintLabel.textColor = .secondaryLabelColor
        viewModel.setPlatformDraft(platform: platform, minimumOS: minimumOS, sdk: sdk)
    }

    private func parseVersion(from string: String) -> MachOVersion? {
        let parts = string
            .split(separator: ".")
            .map(String.init)
            .compactMap(Int.init)

        guard (2...3).contains(parts.count) else { return nil }
        return MachOVersion(
            major: parts[0],
            minor: parts[1],
            patch: parts.count == 3 ? parts[2] : 0
        )
    }

    private func title(for platform: MachOPlatform) -> String {
        switch platform {
        case .macOS:
            return "macOS"
        case .iOS:
            return "iOS"
        case .tvOS:
            return "tvOS"
        case .watchOS:
            return "watchOS"
        case .bridgeOS:
            return "bridgeOS"
        case .macCatalyst:
            return "macCatalyst"
        case .iOSSimulator:
            return "iOS Simulator"
        case .tvOSSimulator:
            return "tvOS Simulator"
        case .watchOSSimulator:
            return "watchOS Simulator"
        case .driverKit:
            return "DriverKit"
        case .visionOS:
            return "visionOS"
        case .visionOSSimulator:
            return "visionOS Simulator"
        case .firmware:
            return "Firmware"
        case .sepOS:
            return "sepOS"
        case let .unknown(rawValue):
            return "unknown(\(rawValue))"
        }
    }

    private func platform(for title: String) -> MachOPlatform? {
        supportedPlatforms.first { self.title(for: $0) == title }
    }

    private func commandTitle(for command: UInt32) -> String {
        "Load Command 0x" + String(command, radix: 16, uppercase: true)
    }

    private func makeTab(label: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: label)
        item.label = label
        item.view = view
        return item
    }

    private func wrappedContentView(for content: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12),
            content.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -12),
        ])

        return container
    }

    private func wrappedScrollingView(for content: NSView) -> NSView {
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(content)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -12),
            content.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -12),
            content.widthAnchor.constraint(equalTo: documentView.widthAnchor, constant: -24),
        ])

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = documentView

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func clearArrangedSubviews(from stackView: NSStackView) {
        for arrangedSubview in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
    }

    private func makeFieldLabel(_ string: String) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        return label
    }

    private func presentOperationError(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

import AppKit
import SnapKit

@MainActor
final class UpdatesPreferencesViewController: NSViewController {
    private let viewModel: UpdatesPreferencesViewModel
    private let strategyOptions = UpdateCheckStrategy.allCases

    private let statusLabel = makeSectionLabel("")
    private let strategyLabel = makeSectionLabel("")
    private let statusValueLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let strategyPopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let automaticDownloadsButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let automaticDownloadsHintLabel = NSTextField(wrappingLabelWithString: "")
    private let checkForUpdatesButton = NSButton(title: "", target: nil, action: nil)

    init(updateManager: UpdateManager) {
        self.viewModel = UpdatesPreferencesViewModel(updateManager: updateManager)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        refreshState()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshState()
    }

    @objc private func strategyChanged(_ sender: NSPopUpButton) {
        guard strategyOptions.indices.contains(sender.indexOfSelectedItem) else {
            return
        }

        viewModel.setUpdateCheckStrategy(strategyOptions[sender.indexOfSelectedItem])
        applyState()
    }

    @objc private func automaticDownloadsChanged(_ sender: NSButton) {
        viewModel.setAutomaticallyDownloadsUpdates(sender.state == .on)
        applyState()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        viewModel.checkForUpdates()
        applyState()
    }

    func reloadLocalization() {
        statusLabel.stringValue = L10n.preferencesUpdatesStatusLabel
        strategyLabel.stringValue = L10n.preferencesUpdatesCheckStrategyLabel
        strategyPopUpButton.removeAllItems()
        strategyPopUpButton.addItems(withTitles: strategyOptions.map(L10n.updateCheckStrategyName(_:)))
        automaticDownloadsButton.title = L10n.preferencesUpdatesAutomaticDownloadsLabel
        automaticDownloadsHintLabel.stringValue = L10n.preferencesUpdatesAutomaticDownloadsHint
        checkForUpdatesButton.title = L10n.preferencesUpdatesCheckNow
        applyState()
    }

    private func buildUI() {
        let statusRow = makeRow(
            label: statusLabel,
            control: statusValueLabel
        )
        let strategyRow = makeRow(
            label: strategyLabel,
            control: strategyPopUpButton
        )

        statusValueLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        detailLabel.font = NSFont.systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor

        strategyPopUpButton.target = self
        strategyPopUpButton.action = #selector(strategyChanged(_:))

        automaticDownloadsButton.target = self
        automaticDownloadsButton.action = #selector(automaticDownloadsChanged(_:))

        automaticDownloadsHintLabel.font = NSFont.systemFont(ofSize: 12)
        automaticDownloadsHintLabel.textColor = .secondaryLabelColor

        checkForUpdatesButton.target = self
        checkForUpdatesButton.action = #selector(checkForUpdates(_:))

        let stack = NSStackView(views: [
            statusRow,
            detailLabel,
            strategyRow,
            automaticDownloadsButton,
            automaticDownloadsHintLabel,
            checkForUpdatesButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18

        view.addSubview(stack)

        statusValueLabel.snp.makeConstraints { make in
            make.width.greaterThanOrEqualTo(180)
        }
        stack.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(24)
            make.trailing.lessThanOrEqualToSuperview().inset(24)
        }

        preferredContentSize = NSSize(width: 640, height: 280)
        reloadLocalization()
    }

    private func refreshState() {
        viewModel.refresh()
        applyState()
    }

    private func applyState() {
        let state = viewModel.state

        statusValueLabel.stringValue = state.statusText
        statusValueLabel.textColor = switch state.statusTone {
        case .ready:
            NSColor.systemGreen
        case .warning:
            NSColor.systemOrange
        }

        detailLabel.stringValue = state.detailText

        if let index = strategyOptions.firstIndex(of: state.updateCheckStrategy) {
            strategyPopUpButton.selectItem(at: index)
        }

        strategyPopUpButton.isEnabled = state.isUpdateStrategyEnabled
        automaticDownloadsButton.isEnabled = state.isAutomaticDownloadsEnabled
        automaticDownloadsButton.state = state.automaticallyDownloadsUpdates ? .on : .off
        checkForUpdatesButton.isEnabled = state.isCheckNowEnabled
    }
}

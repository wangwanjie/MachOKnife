import AppKit

@MainActor
final class UpdatesPreferencesViewController: NSViewController {
    private let viewModel: UpdatesPreferencesViewModel
    private let strategyOptions = UpdateCheckStrategy.allCases

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

    private func buildUI() {
        let statusRow = makeRow(
            label: makeSectionLabel(L10n.preferencesUpdatesStatusLabel),
            control: statusValueLabel
        )
        let strategyRow = makeRow(
            label: makeSectionLabel(L10n.preferencesUpdatesCheckStrategyLabel),
            control: strategyPopUpButton
        )

        statusValueLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        statusValueLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = NSFont.systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        strategyPopUpButton.target = self
        strategyPopUpButton.action = #selector(strategyChanged(_:))
        strategyPopUpButton.translatesAutoresizingMaskIntoConstraints = false
        strategyPopUpButton.addItems(withTitles: strategyOptions.map(L10n.updateCheckStrategyName(_:)))

        automaticDownloadsButton.title = L10n.preferencesUpdatesAutomaticDownloadsLabel
        automaticDownloadsButton.target = self
        automaticDownloadsButton.action = #selector(automaticDownloadsChanged(_:))
        automaticDownloadsButton.translatesAutoresizingMaskIntoConstraints = false

        automaticDownloadsHintLabel.font = NSFont.systemFont(ofSize: 12)
        automaticDownloadsHintLabel.textColor = .secondaryLabelColor
        automaticDownloadsHintLabel.stringValue = L10n.preferencesUpdatesAutomaticDownloadsHint
        automaticDownloadsHintLabel.translatesAutoresizingMaskIntoConstraints = false

        checkForUpdatesButton.title = L10n.preferencesUpdatesCheckNow
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
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            statusValueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
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

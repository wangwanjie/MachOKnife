import AppKit

@MainActor
final class CLIPreferencesViewController: NSViewController {
    private let settings: AppSettings
    private let viewModel: CLIPreferencesViewModel

    private let statusValueLabel = NSTextField(labelWithString: "")
    private let directoryValueLabel = NSTextField(wrappingLabelWithString: "")
    private let executableValueLabel = NSTextField(wrappingLabelWithString: "")
    private let pathHelpLabel = NSTextField(wrappingLabelWithString: "")
    private let chooseDirectoryButton = NSButton(title: "", target: nil, action: nil)
    private let installButton = NSButton(title: "", target: nil, action: nil)
    private let uninstallButton = NSButton(title: "", target: nil, action: nil)

    init(settings: AppSettings, installService: CLIInstallServicing? = nil) {
        self.settings = settings
        let resolvedService = installService ?? CLIInstallService(settings: settings)
        self.viewModel = CLIPreferencesViewModel(installService: resolvedService)
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

    @objc private func chooseDirectory(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = L10n.preferencesCLIChooseDirectory
        panel.prompt = L10n.preferencesCLIChooseDirectory
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = try? settings.cliInstallDirectoryURL()

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        do {
            try settings.setCLIInstallDirectory(selectedURL)
            refreshState()
        } catch {
            presentCLIError(error)
        }
    }

    @objc private func installCLI(_ sender: Any?) {
        do {
            try viewModel.installCLI()
            applyState()
        } catch {
            presentCLIError(error)
        }
    }

    @objc private func uninstallCLI(_ sender: Any?) {
        do {
            try viewModel.uninstallCLI()
            applyState()
        } catch {
            presentCLIError(error)
        }
    }

    private func buildUI() {
        let statusRow = makeRow(
            label: makeSectionLabel(L10n.preferencesCLIStatusLabel),
            control: statusValueLabel
        )
        let directoryRow = makeRow(
            label: makeSectionLabel(L10n.preferencesCLIDirectoryLabel),
            control: directoryValueLabel
        )
        let executableRow = makeRow(
            label: makeSectionLabel(L10n.preferencesCLIExecutableLabel),
            control: executableValueLabel
        )

        statusValueLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        statusValueLabel.translatesAutoresizingMaskIntoConstraints = false

        [directoryValueLabel, executableValueLabel].forEach { label in
            label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            label.lineBreakMode = .byTruncatingMiddle
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
        }

        pathHelpLabel.font = NSFont.systemFont(ofSize: 12)
        pathHelpLabel.textColor = .secondaryLabelColor
        pathHelpLabel.translatesAutoresizingMaskIntoConstraints = false

        chooseDirectoryButton.title = L10n.preferencesCLIChooseDirectory
        chooseDirectoryButton.target = self
        chooseDirectoryButton.action = #selector(chooseDirectory(_:))

        installButton.title = L10n.preferencesCLIInstall
        installButton.target = self
        installButton.action = #selector(installCLI(_:))

        uninstallButton.title = L10n.preferencesCLIUninstall
        uninstallButton.target = self
        uninstallButton.action = #selector(uninstallCLI(_:))

        let buttonsRow = NSStackView(views: [chooseDirectoryButton, installButton, uninstallButton])
        buttonsRow.orientation = .horizontal
        buttonsRow.alignment = .centerY
        buttonsRow.spacing = 8
        buttonsRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [statusRow, directoryRow, executableRow, buttonsRow, pathHelpLabel])
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
        do {
            try viewModel.refresh()
            applyState()
        } catch {
            presentCLIError(error)
        }
    }

    private func applyState() {
        switch viewModel.state {
        case .notConfigured:
            statusValueLabel.stringValue = L10n.preferencesCLIStatusNotConfigured
            statusValueLabel.textColor = .secondaryLabelColor
            directoryValueLabel.stringValue = L10n.preferencesCLIDirectoryNotConfigured
            executableValueLabel.stringValue = L10n.preferencesCLIExecutableNotInstalled
            installButton.isEnabled = false
            uninstallButton.isEnabled = false
            pathHelpLabel.stringValue = L10n.preferencesCLIPathHelpGeneric

        case let .readyToInstall(installDirectory):
            statusValueLabel.stringValue = L10n.preferencesCLIStatusReadyToInstall
            statusValueLabel.textColor = .labelColor
            directoryValueLabel.stringValue = installDirectory.path
            executableValueLabel.stringValue = L10n.preferencesCLIExecutableNotInstalled
            installButton.isEnabled = true
            uninstallButton.isEnabled = false
            pathHelpLabel.stringValue = L10n.preferencesCLIPathHelp(directoryPath: installDirectory.path)

        case let .installed(installedCLIURL):
            let installDirectory = installedCLIURL.deletingLastPathComponent()
            statusValueLabel.stringValue = L10n.preferencesCLIStatusInstalled
            statusValueLabel.textColor = NSColor.systemGreen
            directoryValueLabel.stringValue = installDirectory.path
            executableValueLabel.stringValue = installedCLIURL.path
            installButton.isEnabled = true
            uninstallButton.isEnabled = true
            pathHelpLabel.stringValue = L10n.preferencesCLIPathHelp(directoryPath: installDirectory.path)
        }
    }

    private func presentCLIError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.preferencesCLIErrorTitle
        alert.informativeText = L10n.preferencesCLIErrorMessage(for: error)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

import AppKit
import SnapKit

@MainActor
final class CLIPreferencesViewController: NSViewController {
    private enum LastAction {
        case idle
        case installed(path: String)
        case uninstalled(path: String)
        case failed(message: String)
    }

    private let settings: AppSettings
    private let viewModel: CLIPreferencesViewModel
    private var settingsObserver: NSObjectProtocol?
    private var lastAction: LastAction = .idle

    private let statusLabel = makeSectionLabel("")
    private let directoryLabel = makeSectionLabel("")
    private let executableLabel = makeSectionLabel("")
    private let lastActionLabel = makeSectionLabel("")
    private let statusValueLabel = NSTextField(labelWithString: "")
    private let directoryValueLabel = NSTextField(wrappingLabelWithString: "")
    private let executableValueLabel = NSTextField(wrappingLabelWithString: "")
    private let lastActionValueLabel = NSTextField(wrappingLabelWithString: "")
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
        observeSettings()
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
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
            statusValueLabel.stringValue = L10n.preferencesCLIStatusReadyToInstall
            try viewModel.installCLI()
            applyState()
            switch viewModel.state {
            case let .installed(installedCLIURL):
                lastAction = .installed(path: installedCLIURL.path)
            case let .readyToInstall(installDirectory):
                let executablePath = installDirectory
                    .appendingPathComponent("machoe-cli", isDirectory: false)
                    .path
                lastAction = .failed(message: L10n.preferencesCLIInstallIncomplete(path: executablePath))
            case .notConfigured:
                lastAction = .failed(message: L10n.preferencesCLIErrorMessage(for: CLIInstallError.installDirectoryNotConfigured))
            }
            applyLastActionText()
        } catch {
            presentCLIError(error)
        }
    }

    @objc private func uninstallCLI(_ sender: Any?) {
        do {
            let removedPath = viewModel.state.installedCLIURL?.path
            try viewModel.uninstallCLI()
            applyState()
            if let removedPath {
                lastAction = .uninstalled(path: removedPath)
                applyLastActionText()
            }
        } catch {
            presentCLIError(error)
        }
    }

    func reloadLocalization() {
        statusLabel.stringValue = L10n.preferencesCLIStatusLabel
        directoryLabel.stringValue = L10n.preferencesCLIDirectoryLabel
        executableLabel.stringValue = L10n.preferencesCLIExecutableLabel
        lastActionLabel.stringValue = L10n.preferencesCLILastActionLabel
        chooseDirectoryButton.title = L10n.preferencesCLIChooseDirectory
        installButton.title = L10n.preferencesCLIInstall
        uninstallButton.title = L10n.preferencesCLIUninstall
        applyLastActionText()
        applyState()
    }

    private func buildUI() {
        let statusRow = makeRow(
            label: statusLabel,
            control: statusValueLabel
        )
        let directoryRow = makeRow(
            label: directoryLabel,
            control: directoryValueLabel
        )
        let executableRow = makeRow(
            label: executableLabel,
            control: executableValueLabel
        )
        let lastActionRow = makeRow(
            label: lastActionLabel,
            control: lastActionValueLabel
        )

        statusValueLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        [directoryValueLabel, executableValueLabel].forEach { label in
            label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            label.lineBreakMode = .byTruncatingMiddle
            label.textColor = .secondaryLabelColor
        }

        lastActionValueLabel.font = NSFont.systemFont(ofSize: 12)
        lastActionValueLabel.textColor = .secondaryLabelColor

        pathHelpLabel.font = NSFont.systemFont(ofSize: 12)
        pathHelpLabel.textColor = .secondaryLabelColor

        chooseDirectoryButton.target = self
        chooseDirectoryButton.action = #selector(chooseDirectory(_:))

        installButton.target = self
        installButton.action = #selector(installCLI(_:))

        uninstallButton.target = self
        uninstallButton.action = #selector(uninstallCLI(_:))

        let buttonsRow = NSStackView(views: [chooseDirectoryButton, installButton, uninstallButton])
        buttonsRow.orientation = .horizontal
        buttonsRow.alignment = .centerY
        buttonsRow.spacing = 8

        let stack = NSStackView(views: [statusRow, directoryRow, executableRow, lastActionRow, buttonsRow, pathHelpLabel])
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
            make.bottom.equalToSuperview().inset(24)
        }

        preferredContentSize = NSSize(width: 640, height: 0)
        applyLastActionText()
        reloadLocalization()
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
        statusValueLabel.stringValue = error.localizedDescription
        statusValueLabel.textColor = .systemRed
        lastAction = .failed(message: error.localizedDescription)
        applyLastActionText()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.preferencesCLIErrorTitle
        alert.informativeText = L10n.preferencesCLIErrorMessage(for: error)
        alert.addButton(withTitle: "OK")
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.didChangeNotification,
            object: settings,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshState()
                self?.reloadLocalization()
            }
        }
    }

    private func applyLastActionText() {
        switch lastAction {
        case .idle:
            lastActionValueLabel.stringValue = L10n.preferencesCLILastActionIdle
        case let .installed(path):
            lastActionValueLabel.stringValue = L10n.preferencesCLISuccessInstall(path: path)
        case let .uninstalled(path):
            lastActionValueLabel.stringValue = L10n.preferencesCLISuccessUninstall(path: path)
        case let .failed(message):
            lastActionValueLabel.stringValue = message
        }
    }
}

private extension CLIPreferencesViewModel.State {
    var installedCLIURL: URL? {
        guard case let .installed(installedCLIURL) = self else { return nil }
        return installedCLIURL
    }
}

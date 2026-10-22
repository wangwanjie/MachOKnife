import Foundation
import Testing
@testable import MachOKnife

@MainActor
struct CLIPreferencesViewModelTests {
    @Test("refresh shows ready-to-install state when a directory is configured but no CLI is installed")
    func refreshShowsReadyToInstallState() throws {
        let installDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = StubCLIInstallService(
            currentStatus: CLIInstallStatus(
                installDirectoryURL: installDirectory,
                installedCLIURL: installDirectory.appendingPathComponent("machoe-cli"),
                isInstalled: false
            )
        )
        let viewModel = CLIPreferencesViewModel(installService: service)

        try viewModel.refresh()

        #expect(viewModel.state == .readyToInstall(installDirectory: installDirectory))
    }

    @Test("install updates the view model to installed state")
    func installUpdatesTheViewModelToInstalledState() throws {
        let installDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let installedCLIURL = installDirectory.appendingPathComponent("machoe-cli")
        let service = StubCLIInstallService(
            currentStatus: CLIInstallStatus(
                installDirectoryURL: installDirectory,
                installedCLIURL: installedCLIURL,
                isInstalled: false
            ),
            installStatus: CLIInstallStatus(
                installDirectoryURL: installDirectory,
                installedCLIURL: installedCLIURL,
                isInstalled: true
            )
        )
        let viewModel = CLIPreferencesViewModel(installService: service)

        try viewModel.installCLI()

        #expect(viewModel.state == .installed(installedCLIURL: installedCLIURL))
    }

    @Test("uninstall updates the view model back to ready-to-install state")
    func uninstallUpdatesTheViewModelBackToReadyToInstallState() throws {
        let installDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let installedCLIURL = installDirectory.appendingPathComponent("machoe-cli")
        let service = StubCLIInstallService(
            currentStatus: CLIInstallStatus(
                installDirectoryURL: installDirectory,
                installedCLIURL: installedCLIURL,
                isInstalled: true
            ),
            uninstallStatus: CLIInstallStatus(
                installDirectoryURL: installDirectory,
                installedCLIURL: installedCLIURL,
                isInstalled: false
            )
        )
        let viewModel = CLIPreferencesViewModel(installService: service)

        try viewModel.uninstallCLI()

        #expect(viewModel.state == .readyToInstall(installDirectory: installDirectory))
    }

    @Test("refresh shows not-configured state when no install directory is chosen")
    func refreshShowsNotConfiguredState() throws {
        let service = StubCLIInstallService(
            currentStatus: CLIInstallStatus(installDirectoryURL: nil, installedCLIURL: nil, isInstalled: false)
        )
        let viewModel = CLIPreferencesViewModel(installService: service)

        try viewModel.refresh()

        #expect(viewModel.state == .notConfigured)
    }

    @Test("an installed status without an executable URL falls back to ready-to-install")
    func installedStatusWithoutURLFallsBackToReadyToInstall() throws {
        let installDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = StubCLIInstallService(
            currentStatus: CLIInstallStatus(installDirectoryURL: installDirectory, installedCLIURL: nil, isInstalled: true)
        )
        let viewModel = CLIPreferencesViewModel(installService: service)

        try viewModel.refresh()

        #expect(viewModel.state == .readyToInstall(installDirectory: installDirectory))
    }

    @Test("service errors propagate and keep the previous state")
    func serviceErrorsPropagateAndKeepState() throws {
        let installDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = StubCLIInstallService(
            currentStatus: CLIInstallStatus(
                installDirectoryURL: installDirectory,
                installedCLIURL: installDirectory.appendingPathComponent("machoe-cli"),
                isInstalled: false
            ),
            installError: CLIInstallError.bundledCLINotFound
        )
        let viewModel = CLIPreferencesViewModel(installService: service)
        try viewModel.refresh()

        #expect(throws: CLIInstallError.bundledCLINotFound) {
            try viewModel.installCLI()
        }
        #expect(viewModel.state == .readyToInstall(installDirectory: installDirectory))
    }
}

private final class StubCLIInstallService: CLIInstallServicing {
    private let currentStatus: CLIInstallStatus
    private let installStatus: CLIInstallStatus?
    private let uninstallStatus: CLIInstallStatus?
    private let installError: Error?

    init(
        currentStatus: CLIInstallStatus,
        installStatus: CLIInstallStatus? = nil,
        uninstallStatus: CLIInstallStatus? = nil,
        installError: Error? = nil
    ) {
        self.currentStatus = currentStatus
        self.installStatus = installStatus
        self.uninstallStatus = uninstallStatus
        self.installError = installError
    }

    func status() throws -> CLIInstallStatus {
        currentStatus
    }

    func install() throws -> CLIInstallStatus {
        if let installError {
            throw installError
        }
        return installStatus ?? currentStatus
    }

    func uninstall() throws -> CLIInstallStatus {
        uninstallStatus ?? currentStatus
    }
}

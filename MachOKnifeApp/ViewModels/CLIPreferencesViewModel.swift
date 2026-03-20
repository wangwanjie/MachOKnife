import Foundation

@MainActor
final class CLIPreferencesViewModel {
    enum State: Equatable {
        case notConfigured
        case readyToInstall(installDirectory: URL)
        case installed(installedCLIURL: URL)
    }

    private let installService: CLIInstallServicing

    private(set) var state: State = .notConfigured

    init(installService: CLIInstallServicing) {
        self.installService = installService
    }

    func refresh() throws {
        state = try Self.makeState(from: installService.status())
    }

    func installCLI() throws {
        state = try Self.makeState(from: installService.install())
    }

    func uninstallCLI() throws {
        state = try Self.makeState(from: installService.uninstall())
    }

    private static func makeState(from status: CLIInstallStatus) throws -> State {
        guard let installDirectory = status.installDirectoryURL else {
            return .notConfigured
        }

        if status.isInstalled, let installedCLIURL = status.installedCLIURL {
            return .installed(installedCLIURL: installedCLIURL)
        }

        return .readyToInstall(installDirectory: installDirectory)
    }
}

import Foundation

struct CLIInstallStatus: Equatable {
    let installDirectoryURL: URL?
    let installedCLIURL: URL?
    let isInstalled: Bool
}

enum CLIInstallError: Error {
    case installDirectoryNotConfigured
    case bundledCLINotFound
}

protocol CLIInstallServicing {
    func status() throws -> CLIInstallStatus
    func install() throws -> CLIInstallStatus
    func uninstall() throws -> CLIInstallStatus
}

final class CLIInstallService: CLIInstallServicing {
    typealias BundledCLIURLProvider = () throws -> URL?

    private let settings: AppSettings
    private let fileManager: FileManager
    private let bundledCLIURLProvider: BundledCLIURLProvider

    init(
        settings: AppSettings = .shared,
        fileManager: FileManager = .default,
        bundledCLIURLProvider: @escaping BundledCLIURLProvider = CLIInstallService.defaultBundledCLIURL
    ) {
        self.settings = settings
        self.fileManager = fileManager
        self.bundledCLIURLProvider = bundledCLIURLProvider
    }

    func status() throws -> CLIInstallStatus {
        let installDirectoryURL = try settings.cliInstallDirectoryURL()
        let installedCLIURL = installDirectoryURL?.appendingPathComponent("machoe-cli", isDirectory: false)
        let isInstalled = installedCLIURL.map { fileManager.isExecutableFile(atPath: $0.path) } ?? false

        return CLIInstallStatus(
            installDirectoryURL: installDirectoryURL,
            installedCLIURL: installedCLIURL,
            isInstalled: isInstalled
        )
    }

    @discardableResult
    func install() throws -> CLIInstallStatus {
        guard let installDirectoryURL = try settings.cliInstallDirectoryURL() else {
            throw CLIInstallError.installDirectoryNotConfigured
        }
        guard let bundledCLIURL = try bundledCLIURLProvider() else {
            throw CLIInstallError.bundledCLINotFound
        }

        let installedCLIURL = installDirectoryURL.appendingPathComponent("machoe-cli", isDirectory: false)

        try accessDirectory(installDirectoryURL) {
            try fileManager.createDirectory(at: installDirectoryURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: installedCLIURL.path) {
                try fileManager.removeItem(at: installedCLIURL)
            }
            try fileManager.copyItem(at: bundledCLIURL, to: installedCLIURL)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedCLIURL.path)
        }

        return try status()
    }

    @discardableResult
    func uninstall() throws -> CLIInstallStatus {
        let currentStatus = try status()
        guard let installedCLIURL = currentStatus.installedCLIURL else {
            return currentStatus
        }

        try accessDirectory(currentStatus.installDirectoryURL) {
            if fileManager.fileExists(atPath: installedCLIURL.path) {
                try fileManager.removeItem(at: installedCLIURL)
            }
        }

        return try status()
    }

    private func accessDirectory<T>(_ url: URL?, operation: () throws -> T) throws -> T {
        let didAccess = url?.startAccessingSecurityScopedResource() ?? false
        defer {
            if didAccess {
                url?.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }

    nonisolated private static func defaultBundledCLIURL() throws -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("CLI/machoe-cli", isDirectory: false),
            Bundle.main.sharedSupportURL?.appendingPathComponent("machoe-cli", isDirectory: false),
            Bundle.main.resourceURL?.appendingPathComponent("machoe-cli", isDirectory: false),
            Bundle.main.url(forAuxiliaryExecutable: "machoe-cli"),
        ]

        return candidates.compactMap { $0 }.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }
}

import AppKit
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
    typealias FallbackExecutableProbe = (URL) -> Bool

    private let settings: AppSettings
    private let fileManager: FileManager
    private let fallbackExecutableProbe: FallbackExecutableProbe
    private let bundledCLIURLProvider: BundledCLIURLProvider

    init(
        settings: AppSettings = .shared,
        fileManager: FileManager = .default,
        fallbackExecutableProbe: @escaping FallbackExecutableProbe = CLIInstallService.defaultFallbackExecutableProbe,
        bundledCLIURLProvider: @escaping BundledCLIURLProvider = CLIInstallService.defaultBundledCLIURL
    ) {
        self.settings = settings
        self.fileManager = fileManager
        self.fallbackExecutableProbe = fallbackExecutableProbe
        self.bundledCLIURLProvider = bundledCLIURLProvider
    }

    func status() throws -> CLIInstallStatus {
        let installDirectoryURL = try settings.cliInstallDirectoryURL()
        return try accessDirectory(installDirectoryURL) {
            let installedCLIURL = installDirectoryURL?.appendingPathComponent("machoe-cli", isDirectory: false)
            let isInstalled = installedCLIURL.map {
                isInstalledCLI(at: $0)
            } ?? false

            return CLIInstallStatus(
                installDirectoryURL: installDirectoryURL,
                installedCLIURL: installedCLIURL,
                isInstalled: isInstalled
            )
        }
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

        do {
            try accessDirectory(installDirectoryURL) {
                try fileManager.createDirectory(at: installDirectoryURL, withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: installedCLIURL.path) {
                    try fileManager.removeItem(at: installedCLIURL)
                }
                try fileManager.copyItem(at: bundledCLIURL, to: installedCLIURL)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedCLIURL.path)
            }
        } catch {
            guard requiresAdministratorPrivileges(error) else {
                throw error
            }
            try installWithPrivileges(sourceURL: bundledCLIURL, destinationURL: installedCLIURL)
        }

        settings.setLastKnownCLIExecutablePath(installedCLIURL.path)
        return try status()
    }

    @discardableResult
    func uninstall() throws -> CLIInstallStatus {
        let currentStatus = try status()
        guard let installedCLIURL = currentStatus.installedCLIURL else {
            return currentStatus
        }

        do {
            try accessDirectory(currentStatus.installDirectoryURL) {
                if fileManager.fileExists(atPath: installedCLIURL.path) {
                    try fileManager.removeItem(at: installedCLIURL)
                }
            }
        } catch {
            guard requiresAdministratorPrivileges(error) else {
                throw error
            }
            try removeWithPrivileges(url: installedCLIURL)
        }

        settings.clearLastKnownCLIExecutablePath()
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

    private func isInstalledCLI(at url: URL) -> Bool {
        if fileManager.fileExists(atPath: url.path), fileManager.isExecutableFile(atPath: url.path) {
            return true
        }

        // Release builds run inside App Sandbox, so privileged installs to system bin directories
        // may succeed while direct sandbox file probes still report the CLI as missing.
        if fallbackExecutableProbe(url) {
            return true
        }

        return settings.lastKnownCLIExecutablePath() == url.path
    }

    nonisolated private static func defaultBundledCLIURL() throws -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("CLI/machoe-cli", isDirectory: false),
            Bundle.main.sharedSupportURL?.appendingPathComponent("machoe-cli", isDirectory: false),
            Bundle.main.resourceURL?.appendingPathComponent("machoe-cli", isDirectory: false),
            Bundle.main.url(forAuxiliaryExecutable: "machoe-cli"),
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("machoe-cli", isDirectory: false),
        ]

        return candidates.compactMap { $0 }.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    nonisolated private static func defaultFallbackExecutableProbe(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "test -x \(shellQuoted(url.path))"]

        do {
            try process.run()
        } catch {
            return false
        }

        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func requiresAdministratorPrivileges(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteNoPermissionError
    }

    private func installWithPrivileges(sourceURL: URL, destinationURL: URL) throws {
        let script = """
        do shell script "mkdir -p \(Self.shellQuoted(destinationURL.deletingLastPathComponent().path)) && /usr/bin/install -m 755 \(Self.shellQuoted(sourceURL.path)) \(Self.shellQuoted(destinationURL.path))" with administrator privileges
        """
        try runPrivileged(script: script)
    }

    private func removeWithPrivileges(url: URL) throws {
        let script = """
        do shell script "if [ -e \(Self.shellQuoted(url.path)) ]; then /bin/rm -f \(Self.shellQuoted(url.path)); fi" with administrator privileges
        """
        try runPrivileged(script: script)
    }

    private func runPrivileged(script: String) throws {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(&error)
        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "Administrator command failed."
            throw NSError(domain: "MachOKnife.CLIInstall", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    nonisolated private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

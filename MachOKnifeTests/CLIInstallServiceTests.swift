import Foundation
import Testing
@testable import MachOKnife

struct CLIInstallServiceTests {
    @Test("install copies the bundled CLI into the selected directory")
    func installCopiesBundledCLIIntoSelectedDirectory() throws {
        let environment = try makeEnvironment()
        let settings = AppSettings(defaults: environment.defaults)
        try settings.setCLIInstallDirectory(environment.installDirectory)

        let service = CLIInstallService(
            settings: settings,
            bundledCLIURLProvider: { environment.bundledCLIURL }
        )

        let status = try service.install()

        #expect(status.isInstalled)
        #expect(status.installedCLIURL == environment.installDirectory.appendingPathComponent("machoe-cli"))
        #expect(FileManager.default.fileExists(atPath: status.installedCLIURL!.path))
        #expect(try String(contentsOf: status.installedCLIURL!, encoding: .utf8) == "#!/bin/sh\necho MachOKnife CLI\n")
    }

    @Test("uninstall removes the installed CLI and clears installed state")
    func uninstallRemovesInstalledCLIAndClearsInstalledState() throws {
        let environment = try makeEnvironment()
        let settings = AppSettings(defaults: environment.defaults)
        try settings.setCLIInstallDirectory(environment.installDirectory)

        let service = CLIInstallService(
            settings: settings,
            bundledCLIURLProvider: { environment.bundledCLIURL }
        )

        _ = try service.install()
        let status = try service.uninstall()

        #expect(status.isInstalled == false)
        #expect(status.installedCLIURL == environment.installDirectory.appendingPathComponent("machoe-cli"))
        #expect(FileManager.default.fileExists(atPath: status.installedCLIURL!.path) == false)
    }

    @Test("status falls back to sandbox probe when direct filesystem checks cannot confirm the CLI")
    func statusFallsBackToSandboxProbeWhenDirectChecksCannotConfirmCLI() throws {
        let environment = try makeEnvironment()
        let settings = AppSettings(defaults: environment.defaults)
        try settings.setCLIInstallDirectory(environment.installDirectory)

        let installedCLIURL = environment.installDirectory.appendingPathComponent("machoe-cli")
        try FileManager.default.copyItem(at: environment.bundledCLIURL, to: installedCLIURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedCLIURL.path)

        let fileManager = RestrictedCLIFileManager(restrictedPath: installedCLIURL.path)
        let service = CLIInstallService(
            settings: settings,
            fileManager: fileManager,
            fallbackExecutableProbe: { url in
                url == installedCLIURL
            },
            bundledCLIURLProvider: { environment.bundledCLIURL }
        )

        let status = try service.status()

        #expect(status.isInstalled)
        #expect(status.installedCLIURL == installedCLIURL)
    }

    @Test("install remembers a successful CLI path when direct validation is unavailable")
    func installRemembersSuccessfulCLIPathWhenDirectValidationIsUnavailable() throws {
        let environment = try makeEnvironment()
        let settings = AppSettings(defaults: environment.defaults)
        try settings.setCLIInstallDirectory(environment.installDirectory)

        let installedCLIURL = environment.installDirectory.appendingPathComponent("machoe-cli")
        let fileManager = RestrictedCLIFileManager(restrictedPath: installedCLIURL.path)
        let service = CLIInstallService(
            settings: settings,
            fileManager: fileManager,
            fallbackExecutableProbe: { _ in false },
            bundledCLIURLProvider: { environment.bundledCLIURL }
        )

        let status = try service.install()

        #expect(status.isInstalled)
        #expect(settings.lastKnownCLIExecutablePath() == installedCLIURL.path)
    }

    @Test("install into the directory that already holds the bundled CLI keeps the file")
    func installIntoBundledCLIDirectoryKeepsTheFile() throws {
        let environment = try makeEnvironment()
        let settings = AppSettings(defaults: environment.defaults)
        // 安装目录就是随包 CLI 所在目录：源文件与目标文件是同一个文件。
        let bundledDirectory = environment.bundledCLIURL.deletingLastPathComponent()
        try settings.setCLIInstallDirectory(bundledDirectory)

        let service = CLIInstallService(
            settings: settings,
            fallbackExecutableProbe: { _ in false },
            bundledCLIURLProvider: { environment.bundledCLIURL }
        )

        let status = try service.install()

        // 回归：此前会先删除目标（也就是源文件）再复制，导致 CLI 丢失且安装失败。
        #expect(status.isInstalled)
        #expect(FileManager.default.fileExists(atPath: environment.bundledCLIURL.path))
        #expect(try String(contentsOf: environment.bundledCLIURL, encoding: .utf8) == "#!/bin/sh\necho MachOKnife CLI\n")
    }

    @Test("install refuses to replace a directory named machoe-cli")
    func installRefusesToReplaceADirectory() throws {
        let environment = try makeEnvironment()
        let settings = AppSettings(defaults: environment.defaults)
        try settings.setCLIInstallDirectory(environment.installDirectory)

        let blockingDirectory = environment.installDirectory.appendingPathComponent("machoe-cli", isDirectory: true)
        let keptFile = blockingDirectory.appendingPathComponent("keep.txt")
        try FileManager.default.createDirectory(at: blockingDirectory, withIntermediateDirectories: true)
        try "user data".write(to: keptFile, atomically: true, encoding: .utf8)

        let service = CLIInstallService(
            settings: settings,
            fallbackExecutableProbe: { _ in false },
            bundledCLIURLProvider: { environment.bundledCLIURL }
        )

        // 回归：此前 `removeItem` 会递归删除该目录及其中的用户数据。
        #expect(throws: CLIInstallError.installPathIsDirectory(blockingDirectory.path)) {
            try service.install()
        }
        #expect(FileManager.default.fileExists(atPath: keptFile.path))
        #expect(settings.lastKnownCLIExecutablePath() == nil)
    }

    @Test("status does not treat a directory named machoe-cli as an installed CLI")
    func statusIgnoresDirectoryNamedLikeTheCLI() throws {
        let environment = try makeEnvironment()
        let settings = AppSettings(defaults: environment.defaults)
        try settings.setCLIInstallDirectory(environment.installDirectory)
        try FileManager.default.createDirectory(
            at: environment.installDirectory.appendingPathComponent("machoe-cli", isDirectory: true),
            withIntermediateDirectories: true
        )

        // 使用默认的 `/bin/sh` 探测：目录也带 x 位，回归前会被误判为已安装。
        let service = CLIInstallService(
            settings: settings,
            bundledCLIURLProvider: { environment.bundledCLIURL }
        )

        #expect(try service.status().isInstalled == false)
    }

    @Test("uninstall refuses to delete a directory named machoe-cli")
    func uninstallRefusesToDeleteADirectory() throws {
        let environment = try makeEnvironment()
        let settings = AppSettings(defaults: environment.defaults)
        try settings.setCLIInstallDirectory(environment.installDirectory)

        let blockingDirectory = environment.installDirectory.appendingPathComponent("machoe-cli", isDirectory: true)
        let keptFile = blockingDirectory.appendingPathComponent("keep.txt")
        try FileManager.default.createDirectory(at: blockingDirectory, withIntermediateDirectories: true)
        try "user data".write(to: keptFile, atomically: true, encoding: .utf8)

        let service = CLIInstallService(
            settings: settings,
            fallbackExecutableProbe: { _ in false },
            bundledCLIURLProvider: { environment.bundledCLIURL }
        )

        #expect(throws: CLIInstallError.self) {
            try service.uninstall()
        }
        #expect(FileManager.default.fileExists(atPath: keptFile.path))
    }

    @Test("install fails with a configuration error when no directory is chosen")
    func installWithoutDirectoryThrowsConfigurationError() throws {
        let environment = try makeEnvironment()
        let settings = AppSettings(defaults: environment.defaults)
        let service = CLIInstallService(
            settings: settings,
            fallbackExecutableProbe: { _ in false },
            bundledCLIURLProvider: { environment.bundledCLIURL }
        )

        #expect(throws: CLIInstallError.installDirectoryNotConfigured) {
            try service.install()
        }
        let status = try service.status()
        #expect(status.installDirectoryURL == nil)
        #expect(status.isInstalled == false)
    }

    @Test("install fails when the bundled CLI is missing")
    func installWithoutBundledCLIThrows() throws {
        let environment = try makeEnvironment()
        let settings = AppSettings(defaults: environment.defaults)
        try settings.setCLIInstallDirectory(environment.installDirectory)
        let service = CLIInstallService(
            settings: settings,
            fallbackExecutableProbe: { _ in false },
            bundledCLIURLProvider: { nil }
        )

        #expect(throws: CLIInstallError.bundledCLINotFound) {
            try service.install()
        }
    }

    @Test("status ignores a remembered install path once the file is known to be missing")
    func statusIgnoresRememberedPathWhenFileIsMissing() throws {
        let environment = try makeEnvironment()
        let settings = AppSettings(defaults: environment.defaults)
        try settings.setCLIInstallDirectory(environment.installDirectory)
        settings.setLastKnownCLIExecutablePath(environment.installDirectory.appendingPathComponent("machoe-cli").path)

        let service = CLIInstallService(
            settings: settings,
            fallbackExecutableProbe: { _ in false },
            bundledCLIURLProvider: { environment.bundledCLIURL }
        )

        #expect(try service.status().isInstalled == false)
    }

    @MainActor
    @Test("CLI install errors describe the actual problem")
    func cliInstallErrorsHaveLocalizedDescriptions() {
        let localization = TestLocalizationOverride(language: .english)
        defer {
            localization.restore()
        }

        // 回归：此前 CLIInstallError 没有 LocalizedError，内联状态只显示系统通用的“操作无法完成”。
        #expect(CLIInstallError.installDirectoryNotConfigured.localizedDescription == L10n.preferencesCLIErrorMessage(for: CLIInstallError.installDirectoryNotConfigured))
        #expect(CLIInstallError.bundledCLINotFound.localizedDescription.contains("machoe-cli"))
        #expect(CLIInstallError.installPathIsDirectory("/tmp/x/machoe-cli").localizedDescription.contains("/tmp/x/machoe-cli"))
    }

    private func makeEnvironment(fileID: String = #fileID, line: Int = #line) throws -> TestEnvironment {
        let suiteName = "MachOKnifeTests.CLIInstallServiceTests.\(fileID).\(line).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let root = FileManager.default.canonicalTemporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundledCLIURL = root.appendingPathComponent("machoe-cli")
        let installDirectory = root.appendingPathComponent("bin", isDirectory: true)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        try "#!/bin/sh\necho MachOKnife CLI\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLIURL.path)

        return TestEnvironment(
            defaults: defaults,
            bundledCLIURL: bundledCLIURL,
            installDirectory: installDirectory
        )
    }
}

private struct TestEnvironment {
    let defaults: UserDefaults
    let bundledCLIURL: URL
    let installDirectory: URL
}

private final class RestrictedCLIFileManager: FileManager {
    private let restrictedPath: String

    init(restrictedPath: String) {
        self.restrictedPath = restrictedPath
        super.init()
    }

    override func fileExists(atPath path: String) -> Bool {
        guard path == restrictedPath else {
            return super.fileExists(atPath: path)
        }
        return false
    }

    override func isExecutableFile(atPath path: String) -> Bool {
        guard path == restrictedPath else {
            return super.isExecutableFile(atPath: path)
        }
        return false
    }
}

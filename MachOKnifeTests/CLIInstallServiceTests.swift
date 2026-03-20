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

    private func makeEnvironment(fileID: String = #fileID, line: Int = #line) throws -> TestEnvironment {
        let suiteName = "MachOKnifeTests.CLIInstallServiceTests.\(fileID).\(line).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let root = FileManager.default.temporaryDirectory
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

import CoreMachO
import Foundation
import Testing
@testable import MachOKnife

struct AppHardeningTests {
    @Test("Retag version parser accepts packed Mach-O versions")
    func retagVersionParserAcceptsValidVersions() {
        #expect(RetagVersionParser.parse("13") == MachOVersion(major: 13, minor: 0, patch: 0))
        #expect(RetagVersionParser.parse("13.1") == MachOVersion(major: 13, minor: 1, patch: 0))
        #expect(RetagVersionParser.parse(" 17.4.1 ") == MachOVersion(major: 17, minor: 4, patch: 1))
        #expect(RetagVersionParser.parse("65535.255.255") == MachOVersion(major: 65535, minor: 255, patch: 255))
    }

    @Test("Retag version parser rejects malformed or out-of-range versions")
    func retagVersionParserRejectsInvalidVersions() {
        for value in ["", ".", "13.", ".1", "13..1", "1.2.3.4", "13.a", "-1", "+1", "65536", "1.256", "1.0.256", "13.0b1", "１３"] {
            #expect(RetagVersionParser.parse(value) == nil, "\(value) should be rejected")
        }
    }

    @Test("XCFramework names gain the extension and reject path components")
    func xcframeworkNameNormalizationAndValidation() {
        #expect(XCFrameworkBuildService.normalizedXCFrameworkName("  Foo ") == "Foo.xcframework")
        #expect(XCFrameworkBuildService.normalizedXCFrameworkName("Foo.xcframework") == "Foo.xcframework")
        #expect(XCFrameworkBuildService.normalizedXCFrameworkName("") == "SDK.xcframework")

        #expect(XCFrameworkBuildService.isValidXCFrameworkName("Foo.xcframework"))
        #expect(XCFrameworkBuildService.isValidXCFrameworkName("../Foo.xcframework") == false)
        #expect(XCFrameworkBuildService.isValidXCFrameworkName("a/Foo.xcframework") == false)
        #expect(XCFrameworkBuildService.isValidXCFrameworkName(".xcframework") == false)
        #expect(XCFrameworkBuildService.isValidXCFrameworkName(".Hidden.xcframework") == false)
        #expect(XCFrameworkBuildService.isValidXCFrameworkName("Foo") == false)
    }

    @Test("privileged AppleScript escapes backslashes and quotes in the shell command")
    func privilegedScriptEscapesAppleScriptLiteral() {
        let path = #"/tmp/dir "quoted"\back"#
        let command = "/bin/cp -f \(CLIInstallService.shellQuoted(path)) /usr/local/bin/machoe-cli"
        let script = CLIInstallService.privilegedShellScript(command: command)

        #expect(CLIInstallService.appleScriptStringLiteral(#"a"b\c"#) == #""a\"b\\c""#)
        #expect(script.hasPrefix("do shell script \""))
        #expect(script.hasSuffix("\" with administrator privileges"))
        #expect(script.contains(#"\"quoted\"\\back"#))

        // The generated source must compile as a single AppleScript string literal.
        let appleScript = NSAppleScript(source: script)
        var compileError: NSDictionary?
        #expect(appleScript?.compileAndReturnError(&compileError) == true, "\(String(describing: compileError))")
    }

    @Test("isKnownMissing only reports paths that definitely do not exist")
    func isKnownMissingDistinguishesMissingPaths() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("machoe-cli")
        try Data().write(to: file)

        #expect(CLIInstallService.isKnownMissing(path: file.path) == false)
        #expect(CLIInstallService.isKnownMissing(path: directory.appendingPathComponent("missing").path))
        #expect(CLIInstallService.isKnownMissing(path: file.appendingPathComponent("child").path))
    }

    @Test("settings notifications carry the kind of change")
    func settingsNotificationsCarryChangeKind() {
        let suiteName = "AppHardeningTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        var changes: [AppSettings.Change] = []
        let observer = NotificationCenter.default.addObserver(
            forName: AppSettings.didChangeNotification,
            object: settings,
            queue: nil
        ) { notification in
            if let change = AppSettings.change(from: notification) {
                changes.append(change)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        settings.recentFilesLimit = 5

        #expect(changes == [.recentFilesLimit])
        #expect(AppSettings.Change.recentFilesLimit.affectsCLIInstallation == false)
        #expect(AppSettings.Change.cliInstallDirectory.affectsCLIInstallation)
        #expect(AppSettings.Change.cliExecutable.affectsCLIInstallation)
    }
}

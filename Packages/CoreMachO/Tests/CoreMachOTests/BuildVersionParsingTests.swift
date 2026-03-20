import Foundation
import MachO
import Testing
@testable import CoreMachO

struct BuildVersionParsingTests {
    @Test("parses build version, install-name metadata, and segment protections")
    func parsesBuildVersionInstallNameAndSegmentProtections() throws {
        let fixtureURL = try BuildVersionFixtureFactory.makeDynamicLibraryFixture()

        let container = try MachOContainer.parse(at: fixtureURL)
        let slice = try #require(container.slices.first)
        let buildVersion = try #require(slice.buildVersion)
        let installNameInfo = try #require(slice.installNameInfo)
        let textSegment = try #require(slice.segments.first(where: { $0.name == "__TEXT" }))

        #expect(buildVersion.platform == .macOS)
        #expect(buildVersion.minimumOS.major == 13)
        #expect(buildVersion.sdk.major >= 13)

        #expect(installNameInfo.path == "@rpath/libBuildVersionFixture.dylib")
        #expect(installNameInfo.command == UInt32(LC_ID_DYLIB))
        #expect(installNameInfo.commandOffset > 0)

        #expect(textSegment.maxProtection.contains(.read))
        #expect(textSegment.initialProtection.contains(.execute))
        #expect(textSegment.sections.isEmpty == false)
    }
}

private enum BuildVersionFixtureFactory {
    static func makeDynamicLibraryFixture() throws -> URL {
        let source = """
        int machoknife_build_version_fixture(void) { return 321; }
        """
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let sourceURL = tempDirectory.appendingPathComponent("fixture.c")
        let outputURL = tempDirectory.appendingPathComponent("libBuildVersionFixture.dylib")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

        try FixtureShell.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-macos13.0",
                "-dynamiclib",
                sourceURL.path,
                "-Wl,-install_name,@rpath/libBuildVersionFixture.dylib",
                "-o",
                outputURL.path,
            ]
        )

        return outputURL
    }
}

private enum FixtureShell {
    static func run(launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: launchPath)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "unknown error"
            throw FixtureShellError.commandFailed(launchPath: launchPath, arguments: arguments, output: errorOutput)
        }
    }
}

private enum FixtureShellError: Error {
    case commandFailed(launchPath: String, arguments: [String], output: String)
}

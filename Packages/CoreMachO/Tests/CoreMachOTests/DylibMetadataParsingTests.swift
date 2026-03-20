import Foundation
import Testing
@testable import CoreMachO

struct DylibMetadataParsingTests {
    @Test("extracts dylib paths and rpaths from a dynamic library fixture")
    func extractsDylibPathsAndRPathsFromDynamicLibraryFixture() throws {
        let fixtureURL = try DylibFixtureFactory.makeDynamicLibraryFixture()

        let container = try MachOContainer.parse(at: fixtureURL)
        let slice = try #require(container.slices.first)

        #expect(slice.dylibReferences.contains(where: { $0.path.contains("libSystem") }))
        #expect(slice.rpaths.contains("@loader_path/Frameworks"))
        #expect(slice.installName == "@rpath/libMachOKnifeFixture.dylib")
    }
}

private enum DylibFixtureFactory {
    static func makeDynamicLibraryFixture() throws -> URL {
        let source = """
        int machoknife_dynamic_fixture(void) { return 123; }
        """
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let sourceURL = tempDirectory.appendingPathComponent("fixture.c")
        let outputURL = tempDirectory.appendingPathComponent("libMachOKnifeFixture.dylib")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

        try Shell.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-macos13.0",
                "-dynamiclib",
                sourceURL.path,
                "-Wl,-install_name,@rpath/libMachOKnifeFixture.dylib",
                "-Wl,-rpath,@loader_path/Frameworks",
                "-o",
                outputURL.path,
            ]
        )

        return outputURL
    }
}

private enum Shell {
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
            throw ShellError.commandFailed(launchPath: launchPath, arguments: arguments, output: errorOutput)
        }
    }
}

private enum ShellError: Error {
    case commandFailed(launchPath: String, arguments: [String], output: String)
}

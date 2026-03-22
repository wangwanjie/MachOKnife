import Foundation
import Testing
@testable import CoreMachO

struct ArchiveInspectorTests {
    @Test("inspects a thin archive without external toolchain helpers")
    func inspectsThinArchive() throws {
        let fixture = try ArchiveFixtureFactory.makeThinArchiveFixture()
        let inspector = ArchiveInspector()

        let inspection = try #require(try inspector.inspect(url: fixture.archiveURL))
        let extraction = try inspector.extractThinArchive(url: fixture.archiveURL)
        let members = try inspector.listMembers(in: extraction.archiveURL)

        #expect(inspection.kind == .archive)
        #expect(inspection.architectures == ["arm64"])
        #expect(members.contains("archive-fixture.o"))
    }

    @Test("inspects a fat archive and extracts the requested architecture without external tools")
    func inspectsFatArchive() throws {
        let fixture = try ArchiveFixtureFactory.makeFatArchiveFixture()
        let inspector = ArchiveInspector()

        let inspection = try #require(try inspector.inspect(url: fixture.archiveURL))
        let extraction = try inspector.extractThinArchive(url: fixture.archiveURL, preferredArchitecture: "arm64")
        let members = try inspector.listMembers(in: extraction.archiveURL)

        #expect(inspection.kind == .fatArchive)
        #expect(inspection.architectures.contains("arm64"))
        #expect(inspection.architectures.contains("x86_64"))
        #expect(members.contains("archive-fixture-arm64.o"))
    }
}

private struct ArchiveFixture {
    let directory: URL
    let archiveURL: URL
}

private enum ArchiveFixtureFactory {
    static func makeThinArchiveFixture() throws -> ArchiveFixture {
        let directory = try makeFixtureDirectory()
        let sourceURL = directory.appendingPathComponent("archive-fixture.c")
        let objectURL = directory.appendingPathComponent("archive-fixture.o")
        let archiveURL = directory.appendingPathComponent("libArchiveFixture.a")

        try "int archive_fixture_symbol(void) { return 1; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try ArchiveFixtureCommand.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "arm64-apple-ios11.0",
                "-c",
                sourceURL.path,
                "-o",
                objectURL.path,
            ]
        )
        try ArchiveFixtureCommand.run(
            launchPath: "/usr/bin/libtool",
            arguments: [
                "-static",
                "-o",
                archiveURL.path,
                objectURL.path,
            ]
        )

        return ArchiveFixture(directory: directory, archiveURL: archiveURL)
    }

    static func makeFatArchiveFixture() throws -> ArchiveFixture {
        let directory = try makeFixtureDirectory()
        let sourceURL = directory.appendingPathComponent("archive-fixture.c")
        let arm64ObjectURL = directory.appendingPathComponent("archive-fixture-arm64.o")
        let x86ObjectURL = directory.appendingPathComponent("archive-fixture-x86_64.o")
        let arm64ArchiveURL = directory.appendingPathComponent("libArchiveFixture-arm64.a")
        let x86ArchiveURL = directory.appendingPathComponent("libArchiveFixture-x86_64.a")
        let fatArchiveURL = directory.appendingPathComponent("libArchiveFixture-fat.a")

        try "int archive_fixture_symbol(void) { return 2; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        try ArchiveFixtureCommand.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "arm64-apple-ios11.0",
                "-c",
                sourceURL.path,
                "-o",
                arm64ObjectURL.path,
            ]
        )
        try ArchiveFixtureCommand.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-ios11.0-simulator",
                "-c",
                sourceURL.path,
                "-o",
                x86ObjectURL.path,
            ]
        )
        try ArchiveFixtureCommand.run(
            launchPath: "/usr/bin/libtool",
            arguments: [
                "-static",
                "-o",
                arm64ArchiveURL.path,
                arm64ObjectURL.path,
            ]
        )
        try ArchiveFixtureCommand.run(
            launchPath: "/usr/bin/libtool",
            arguments: [
                "-static",
                "-o",
                x86ArchiveURL.path,
                x86ObjectURL.path,
            ]
        )
        try ArchiveFixtureCommand.run(
            launchPath: "/usr/bin/lipo",
            arguments: [
                "-create",
                arm64ArchiveURL.path,
                x86ArchiveURL.path,
                "-output",
                fatArchiveURL.path,
            ]
        )

        return ArchiveFixture(directory: directory, archiveURL: fatArchiveURL)
    }

    private static func makeFixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private enum ArchiveFixtureCommand {
    static func run(launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData + errorData, encoding: .utf8) ?? "unknown error"
            throw ArchiveFixtureError.commandFailed("\(launchPath) \(arguments.joined(separator: " "))\n\(output)")
        }
    }
}

private enum ArchiveFixtureError: Error {
    case commandFailed(String)
}

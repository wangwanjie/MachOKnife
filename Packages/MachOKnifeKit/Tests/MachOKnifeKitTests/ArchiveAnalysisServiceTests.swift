import Foundation
import Testing
@testable import MachOKnifeKit

struct ArchiveAnalysisServiceTests {
    @Test("analyzes fat archive slices without Mach-O parse errors")
    func analyzesFatArchiveSlicesWithoutMachOParseErrors() throws {
        let fixture = try ArchiveFixtureFactory.makeFatArchiveFixture()
        let service = ArchiveAnalysisService()

        let analysis = try #require(try service.analyze(url: fixture.archiveURL))

        #expect(analysis.kind == .fatArchive)
        #expect(analysis.architectures.count == 2)
        #expect(analysis.architectures.map(\.architecture).contains("arm64"))
        #expect(analysis.architectures.map(\.architecture).contains("x86_64"))
        #expect(analysis.architectures.allSatisfy { $0.memberCount == 1 })
        #expect(analysis.architectures.allSatisfy { $0.parsedMemberCount == 1 })
        #expect(analysis.architectures.allSatisfy { $0.dylibReferences.isEmpty })
        #expect(analysis.architectures.allSatisfy { $0.rpaths.isEmpty })
    }
}

private struct ArchiveFixture {
    let directory: URL
    let archiveURL: URL
}

private enum ArchiveFixtureFactory {
    static func makeFatArchiveFixture() throws -> ArchiveFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let sourceURL = directory.appendingPathComponent("archive-fixture.c")
        let arm64ObjectURL = directory.appendingPathComponent("archive-fixture-arm64.o")
        let x86ObjectURL = directory.appendingPathComponent("archive-fixture-x86_64.o")
        let arm64ArchiveURL = directory.appendingPathComponent("libArchiveFixture-arm64.a")
        let x86ArchiveURL = directory.appendingPathComponent("libArchiveFixture-x86_64.a")
        let fatArchiveURL = directory.appendingPathComponent("libArchiveFixture-fat.a")

        try "int archive_fixture_symbol(void) { return 3; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try runTool("/usr/bin/clang", arguments: [
            "-target", "arm64-apple-ios11.0",
            "-c",
            sourceURL.path,
            "-o",
            arm64ObjectURL.path,
        ])
        try runTool("/usr/bin/clang", arguments: [
            "-target", "x86_64-apple-ios11.0-simulator",
            "-c",
            sourceURL.path,
            "-o",
            x86ObjectURL.path,
        ])
        try runTool("/usr/bin/libtool", arguments: [
            "-static",
            "-o",
            arm64ArchiveURL.path,
            arm64ObjectURL.path,
        ])
        try runTool("/usr/bin/libtool", arguments: [
            "-static",
            "-o",
            x86ArchiveURL.path,
            x86ObjectURL.path,
        ])
        try runTool("/usr/bin/lipo", arguments: [
            "-create",
            arm64ArchiveURL.path,
            x86ArchiveURL.path,
            "-output",
            fatArchiveURL.path,
        ])

        return ArchiveFixture(directory: directory, archiveURL: fatArchiveURL)
    }

    private static func runTool(_ launchPath: String, arguments: [String]) throws {
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
            throw ArchiveAnalysisServiceTestError.commandFailed(output)
        }
    }
}

private enum ArchiveAnalysisServiceTestError: Error {
    case commandFailed(String)
}

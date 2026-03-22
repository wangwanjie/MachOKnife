import Foundation
import MachOKnifeKit
import Testing

struct MachOToolServicesTests {
    @Test("summary service reports architecture slices for a fat archive")
    func summaryServiceReportsArchitecturesForFatArchive() throws {
        let fixture = try MachOToolFixtureFactory.makeFatArchiveFixture()
        let service = BinarySummaryService()

        let report = try service.makeReport(for: fixture.archiveURL)
        let rendered = report.renderedText

        #expect(rendered.contains("arm64"))
        #expect(rendered.contains("x86_64"))
        #expect(rendered.contains("Static Archive"))
    }

    @Test("contamination checker flags archive members that do not match the requested platform")
    func contaminationCheckerFlagsPlatformMismatches() throws {
        let fixture = try MachOToolFixtureFactory.makeFatArchiveFixture()
        let service = BinaryContaminationCheckService()

        let report = try service.runCheck(
            at: fixture.archiveURL,
            target: "iphoneos",
            mode: .platform
        )

        #expect(report.mismatchCount == 1)
        #expect(report.renderedText.contains("iphonesimulator"))
    }

    @Test("merge split service can split and merge a fat archive")
    func mergeSplitServiceCanSplitAndMergeFatArchive() throws {
        let fixture = try MachOToolFixtureFactory.makeFatArchiveFixture()
        let service = MachOMergeSplitService()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let architectures = try service.availableArchitectures(for: fixture.archiveURL)
        #expect(architectures.contains("arm64"))
        #expect(architectures.contains("x86_64"))

        let splitOutputs = try service.split(
            inputURL: fixture.archiveURL,
            architectures: architectures,
            outputDirectoryURL: outputDirectory
        )

        #expect(splitOutputs.count == 2)
        #expect(splitOutputs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        let mergedURL = outputDirectory.appendingPathComponent("MergedFixture.a")
        try service.merge(inputURLs: splitOutputs, outputURL: mergedURL)

        let mergedArchitectures = try service.availableArchitectures(for: mergedURL)
        #expect(Set(mergedArchitectures) == Set(["arm64", "x86_64"]))
    }
}

private struct MachOToolFixture {
    let directory: URL
    let archiveURL: URL
}

private enum MachOToolFixtureFactory {
    static func makeFatArchiveFixture() throws -> MachOToolFixture {
        let directory = try makeFixtureDirectory()
        let sourceURL = directory.appendingPathComponent("fixture.c")
        let arm64ObjectURL = directory.appendingPathComponent("fixture-arm64.o")
        let x86ObjectURL = directory.appendingPathComponent("fixture-x86_64.o")
        let arm64ArchiveURL = directory.appendingPathComponent("libFixture-arm64.a")
        let x86ArchiveURL = directory.appendingPathComponent("libFixture-x86_64.a")
        let fatArchiveURL = directory.appendingPathComponent("libFixture-fat.a")

        try "int machoknife_tool_fixture(void) { return 7; }\n"
            .write(to: sourceURL, atomically: true, encoding: .utf8)

        try MachOToolFixtureCommand.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "arm64-apple-ios13.0",
                "-c",
                sourceURL.path,
                "-o",
                arm64ObjectURL.path,
            ]
        )
        try MachOToolFixtureCommand.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-ios13.0-simulator",
                "-c",
                sourceURL.path,
                "-o",
                x86ObjectURL.path,
            ]
        )
        try MachOToolFixtureCommand.run(
            launchPath: "/usr/bin/libtool",
            arguments: [
                "-static",
                "-o",
                arm64ArchiveURL.path,
                arm64ObjectURL.path,
            ]
        )
        try MachOToolFixtureCommand.run(
            launchPath: "/usr/bin/libtool",
            arguments: [
                "-static",
                "-o",
                x86ArchiveURL.path,
                x86ObjectURL.path,
            ]
        )
        try MachOToolFixtureCommand.run(
            launchPath: "/usr/bin/lipo",
            arguments: [
                "-create",
                arm64ArchiveURL.path,
                x86ArchiveURL.path,
                "-output",
                fatArchiveURL.path,
            ]
        )

        return MachOToolFixture(directory: directory, archiveURL: fatArchiveURL)
    }

    private static func makeFixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private enum MachOToolFixtureCommand {
    static func run(launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: launchPath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let output = String(
                data: stdout.fileHandleForReading.readDataToEndOfFile()
                    + stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "unknown error"
            throw MachOToolFixtureError.commandFailed(
                "\(launchPath) \(arguments.joined(separator: " "))\n\(output)"
            )
        }
    }
}

private enum MachOToolFixtureError: Error {
    case commandFailed(String)
}

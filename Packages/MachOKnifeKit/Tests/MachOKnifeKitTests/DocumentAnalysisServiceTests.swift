import Foundation
import Testing
@testable import MachOKnifeKit

struct DocumentAnalysisServiceTests {
    @Test("analyzes a Mach-O file into summary models")
    func analyzesMachOFileIntoSummaryModels() throws {
        let fixtureURL = try MachOKnifeFixtureFactory.makeThinFixture()
        let service = DocumentAnalysisService()

        let analysis = try service.analyze(url: fixtureURL)

        #expect(analysis.fileURL == fixtureURL)
        #expect(analysis.containerKind == .thin)
        #expect(analysis.slices.count == 1)
        #expect(analysis.slices.first?.loadCommandCount ?? 0 > 0)
    }
}

private enum MachOKnifeFixtureFactory {
    static func makeThinFixture() throws -> URL {
        let source = """
        int machoknife_fixture(void) { return 99; }
        """
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let sourceURL = tempDirectory.appendingPathComponent("fixture.c")
        let outputURL = tempDirectory.appendingPathComponent("fixture.o")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/clang")
        process.arguments = [
            "-target", "x86_64-apple-macos13.0",
            "-c",
            sourceURL.path,
            "-o",
            outputURL.path,
        ]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw FixtureError.compileFailed
        }

        return outputURL
    }
}

private enum FixtureError: Error {
    case compileFailed
}

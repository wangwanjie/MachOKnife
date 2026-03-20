import Foundation
import Testing

struct CLISmokeTests {
    @Test("info prints slice summaries")
    func infoPrintsSliceSummaries() throws {
        let fixtureURL = try appDebugDylibURL()
        let output = try runCLI(arguments: ["info", fixtureURL.path])

        #expect(output.contains("Slices:"))
        #expect(output.contains("Install Name: @rpath/MachOKnife.debug.dylib"))
    }

    @Test("list-dylibs prints dylib and rpath entries")
    func listDylibsPrintsDylibAndRPathEntries() throws {
        let fixtureURL = try appDebugDylibURL()
        let output = try runCLI(arguments: ["list-dylibs", fixtureURL.path])

        #expect(output.contains("RPATH"))
        #expect(output.contains("@executable_path/../Frameworks"))
        #expect(output.contains("libSystem"))
    }

    private func runCLI(arguments: [String]) throws -> String {
        let cliURL = try cliProductURL()
        #expect(FileManager.default.isExecutableFile(atPath: cliURL.path), "machoe-cli executable should exist at \(cliURL.path)")

        let process = Process()
        process.executableURL = cliURL
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        #expect(process.terminationStatus == 0, "CLI exited with status \(process.terminationStatus): \(output)")
        return output
    }

    private func cliProductURL() throws -> URL {
        let productsDirectory = try productsDirectory()
        return productsDirectory.appendingPathComponent("machoe-cli")
    }

    private func appDebugDylibURL() throws -> URL {
        let productsDirectory = try productsDirectory()
        let dylibURL = productsDirectory
            .appendingPathComponent("MachOKnife.app")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("MachOKnife.debug.dylib")

        #expect(FileManager.default.fileExists(atPath: dylibURL.path), "fixture dylib should exist at \(dylibURL.path)")
        return dylibURL
    }

    private func productsDirectory() throws -> URL {
        let fileManager = FileManager.default
        let candidateRoots = [
            Bundle.main.bundleURL,
            Bundle(for: BundleProbe.self).bundleURL,
        ]

        for root in candidateRoots {
            var currentURL = root

            for _ in 0..<8 {
                let cliURL = currentURL.appendingPathComponent("machoe-cli")
                let appURL = currentURL.appendingPathComponent("MachOKnife.app")
                if fileManager.isExecutableFile(atPath: cliURL.path),
                   fileManager.fileExists(atPath: appURL.path) {
                    return currentURL
                }
                currentURL.deleteLastPathComponent()
            }
        }

        throw CLITestError.productsDirectoryNotFound
    }
}

private final class BundleProbe: NSObject {}

private enum CLITestError: Error {
    case productsDirectoryNotFound
}

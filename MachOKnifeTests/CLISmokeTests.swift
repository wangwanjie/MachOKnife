import Foundation
import Testing

@Suite(.serialized)
struct CLISmokeTests {
    @Test("info prints slice summaries")
    func infoPrintsSliceSummaries() throws {
        let fixtureURL = try appDebugDylibURL()
        let output = try runCLI(arguments: ["info", fixtureURL.path])

        #expect(output.contains("Slices:"))
        #expect(output.contains("Platform:"))
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

    @Test("retag-platform writes a new file with updated platform metadata")
    func retagPlatformWritesUpdatedPlatformMetadata() throws {
        let outputURL = try makeTemporaryDirectory().appendingPathComponent("retagged.dylib")
        let fixtureURL = try cliEditableFixtureURL()

        let commandOutput = try runCLI(arguments: [
            "retag-platform",
            fixtureURL.path,
            "--platform", "macos",
            "--min", "14.0.0",
            "--sdk", "14.4.0",
            "--output", outputURL.path,
        ])
        let infoOutput = try runCLI(arguments: ["info", outputURL.path])

        #expect(commandOutput.contains("Wrote"))
        #expect(infoOutput.contains("Min OS: 14.0.0"))
        #expect(infoOutput.contains("SDK: 14.4.0"))
    }

    @Test("rewrite-rpath updates matching LC_RPATH entries")
    func rewriteRPathUpdatesMatchingEntries() throws {
        let outputURL = try makeTemporaryDirectory().appendingPathComponent("rpath-rewritten.dylib")
        let fixtureURL = try cliEditableFixtureURL()

        let commandOutput = try runCLI(arguments: [
            "rewrite-rpath",
            fixtureURL.path,
            "--from", "@loader_path/Frameworks",
            "--to", "@executable_path/Frameworks",
            "--output", outputURL.path,
        ])
        let dylibOutput = try runCLI(arguments: ["list-dylibs", outputURL.path])

        #expect(commandOutput.contains("Wrote"))
        #expect(dylibOutput.contains("@executable_path/Frameworks"))
        #expect(dylibOutput.contains("@loader_path/Frameworks") == false)
    }

    @Test("set-id and strip-signature update install name and signature state")
    func setIDAndStripSignatureUpdateInstallNameAndSignatureState() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let fixtureURL = try cliEditableFixtureURL()
        let setIDOutputURL = temporaryDirectory.appendingPathComponent("set-id.dylib")
        let unsignedOutputURL = temporaryDirectory.appendingPathComponent("unsigned.dylib")

        _ = try runCLI(arguments: [
            "set-id",
            fixtureURL.path,
            "--install-name", "@rpath/libCLISetID.dylib",
            "--output", setIDOutputURL.path,
        ])
        _ = try runCLI(arguments: [
            "strip-signature",
            fixtureURL.path,
            "--output", unsignedOutputURL.path,
        ])

        let infoOutput = try runCLI(arguments: ["info", setIDOutputURL.path])
        let validateOutput = try runCLI(arguments: ["validate", unsignedOutputURL.path])

        #expect(infoOutput.contains("Install Name: @rpath/libCLISetID.dylib"))
        #expect(validateOutput.contains("Code Signature: absent"))
    }

    @Test("fix-dyld-cache-dylib rewrites install name dependencies and rpath")
    func fixDyldCacheDylibRewritesInstallNameDependenciesAndRPath() throws {
        let outputURL = try makeTemporaryDirectory().appendingPathComponent("fixed-cache-style.dylib")
        let fixtureURL = try cliCacheStyleFixtureURL()

        let commandOutput = try runCLI(arguments: [
            "fix-dyld-cache-dylib",
            fixtureURL.path,
            "--output", outputURL.path,
        ])
        let dylibOutput = try runCLI(arguments: ["list-dylibs", outputURL.path])
        let infoOutput = try runCLI(arguments: ["info", outputURL.path])

        #expect(commandOutput.contains("Wrote"))
        #expect(infoOutput.contains("Install Name: @rpath/libCacheStyle.dylib"))
        #expect(dylibOutput.contains("@rpath/libCacheDependency.dylib"))
        #expect(dylibOutput.contains("RPATH @loader_path"))
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
    case fixtureNotFound(String)
}

private func cliEditableFixtureURL() throws -> URL {
    try cliFixtureURL(named: "libCLIEditable.dylib")
}

private func cliCacheStyleFixtureURL() throws -> URL {
    try cliFixtureURL(named: "libCacheStyle.dylib")
}

private func cliFixtureURL(named fixtureName: String) throws -> URL {
    let fixtureURL = repoRoot()
        .appendingPathComponent("Resources")
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("cli")
        .appendingPathComponent(fixtureName)

    guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
        throw CLITestError.fixtureNotFound(fixtureURL.path)
    }

    return fixtureURL
}

private func repoRoot() -> URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

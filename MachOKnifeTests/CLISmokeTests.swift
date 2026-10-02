import Foundation
import Testing

@Suite(.serialized)
struct CLISmokeTests {
    @Test("help prints version, author, and command descriptions")
    func helpPrintsVersionAuthorAndCommandDescriptions() throws {
        let output = try runCLI(arguments: ["--help"])

        #expect(output.contains("machoe-cli v\(try projectMarketingVersion())"))
        #expect(output.contains("VanJay"))
        #expect(output.contains("vanjay.dev@gmail.com"))
        #expect(output.contains("summary"))
        #expect(output.contains("Print a concise Mach-O or archive overview."))
        #expect(output.contains("build-xcframework"))
        #expect(output.contains("Package static libraries and headers into an XCFramework."))
    }

    @Test("running without arguments prints help and exits with EX_USAGE")
    func noArgumentsPrintsHelpAndExitsWithUsageStatus() throws {
        let output = try runCLI(arguments: [], expectedStatus: 64)

        #expect(output.contains("Usage:"))
        #expect(output.contains("Commands:"))
    }

    @Test("--version prints the project marketing version")
    func versionPrintsProjectMarketingVersion() throws {
        let output = try runCLI(arguments: ["--version"])

        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "machoe-cli v\(try projectMarketingVersion())")
    }

    @Test("<command> --help prints that command's help")
    func commandHelpPrintsCommandUsage() throws {
        let output = try runCLI(arguments: ["retag-platform", "--help"])

        #expect(output.contains("retag-platform: Rewrite platform, minimum OS, and SDK metadata for a binary."))
        #expect(output.contains("machoe-cli retag-platform <path>"))
        #expect(output.contains("build-xcframework") == false)
    }

    @Test("unknown options are rejected with a usage error")
    func unknownOptionsAreRejected() throws {
        let fixtureURL = try cliEditableFixtureURL()
        let output = try runCLI(arguments: ["info", fixtureURL.path, "--bogus"], expectedStatus: 64)

        #expect(output.contains("unknown option '--bogus'"))
        #expect(output.contains("machoe-cli info <path>"))
    }

    @Test("an option token is never used as the input path")
    func optionTokensAreNotTreatedAsInputPath() throws {
        let outputURL = try makeTemporaryDirectory().appendingPathComponent("stripped.dylib")
        let fixtureURL = try cliEditableFixtureURL()

        let output = try runCLI(arguments: [
            "strip-signature",
            "--output", outputURL.path,
            fixtureURL.path,
        ])

        #expect(output.contains("Wrote: \(outputURL.path)"))
    }

    @Test("build-xcframework refuses an output that is not an .xcframework bundle")
    func buildXCFrameworkRefusesNonXCFrameworkOutput() throws {
        let fixture = try makeXCFrameworkFixture()
        let precious = fixture.directory.appendingPathComponent("precious", isDirectory: true)
        try FileManager.default.createDirectory(at: precious, withIntermediateDirectories: true)
        try "keep".write(to: precious.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let output = try runCLI(arguments: [
            "build-xcframework",
            "--library", fixture.deviceLibraryURL.path,
            "--headers", fixture.headersDirectoryURL.path,
            "--output", precious.path,
        ], expectedStatus: 64)

        #expect(output.contains(".xcframework"))
        #expect(FileManager.default.fileExists(atPath: precious.appendingPathComponent("file.txt").path))
    }

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

    @Test("info handles fat archive inputs")
    func infoHandlesFatArchiveInputs() throws {
        let fixture = try makeFatArchiveFixture()

        let output = try runCLI(arguments: ["info", fixture.archiveURL.path])

        #expect(output.contains("Container: fat archive"))
        #expect(architectureList(in: output) == ["arm64", "x86_64"])
    }

    @Test("list-dylibs handles fat archive inputs without parse errors")
    func listDylibsHandlesFatArchiveInputsWithoutParseErrors() throws {
        let fixture = try makeFatArchiveFixture()

        let output = try runCLI(arguments: ["list-dylibs", fixture.archiveURL.path])

        #expect(output.contains("Container: fat archive"))
        #expect(output.contains("Architecture arm64:"))
        #expect(output.contains("No dylib or RPATH entries found."))
    }

    @Test("summary prints archive architecture details")
    func summaryPrintsArchiveArchitectureDetails() throws {
        let fixture = try makeFatArchiveFixture()

        let output = try runCLI(arguments: ["summary", fixture.archiveURL.path])

        #expect(output.contains("Kind: Fat Archive"))
        #expect(architectureList(in: output) == ["arm64", "x86_64"])
        #expect(output.contains("Members:"))
        #expect(output.contains("Sample Object:"))
    }

    @Test("check-contamination reports architecture mismatches")
    func checkContaminationReportsArchitectureMismatches() throws {
        let fixture = try makeFatArchiveFixture()

        let output = try runCLI(arguments: [
            "check-contamination",
            fixture.archiveURL.path,
            "--mode", "architecture",
            "--target", "arm64",
        ], expectedStatus: 1)

        #expect(output.contains("Mode: architecture"))
        #expect(output.contains("Target: arm64"))
        #expect(output.contains("Mismatches"))
        #expect(output.contains("x86_64"))
    }

    @Test("check-contamination exits successfully when every slice matches")
    func checkContaminationExitsSuccessfullyWithoutMismatches() throws {
        let fixture = try makeFatArchiveFixture()

        let output = try runCLI(arguments: [
            "check-contamination",
            fixture.arm64ArchiveURL.path,
            "--mode", "architecture",
            "--target", "arm64",
        ])

        #expect(output.contains("Target: arm64"))
    }

    @Test("merge accepts inputs placed after --output")
    func mergeAcceptsInputsAfterOutputOption() throws {
        let fixture = try makeFatArchiveFixture()
        let mergedArchiveURL = try makeTemporaryDirectory().appendingPathComponent("Merged.a")

        let mergeOutput = try runCLI(arguments: [
            "merge",
            fixture.arm64ArchiveURL.path,
            "--output", mergedArchiveURL.path,
            fixture.x86ArchiveURL.path,
        ])
        let infoOutput = try runCLI(arguments: ["info", mergedArchiveURL.path])

        #expect(mergeOutput.contains("Merged output: \(mergedArchiveURL.path)"))
        #expect(architectureList(in: infoOutput) == ["arm64", "x86_64"])
    }

    @Test("merge and split roundtrip archive slices")
    func mergeAndSplitRoundtripArchiveSlices() throws {
        let fixture = try makeFatArchiveFixture()
        let temporaryDirectory = try makeTemporaryDirectory()
        let mergedArchiveURL = temporaryDirectory.appendingPathComponent("MergedArchive.a")
        let splitDirectoryURL = temporaryDirectory.appendingPathComponent("SplitOutputs", isDirectory: true)

        let mergeOutput = try runCLI(arguments: [
            "merge",
            fixture.arm64ArchiveURL.path,
            fixture.x86ArchiveURL.path,
            "--output", mergedArchiveURL.path,
        ])
        let splitOutput = try runCLI(arguments: [
            "split",
            mergedArchiveURL.path,
            "--output-dir", splitDirectoryURL.path,
        ])

        #expect(mergeOutput.contains("Merged output: \(mergedArchiveURL.path)"))
        #expect(FileManager.default.fileExists(atPath: mergedArchiveURL.path))
        #expect(splitOutput.contains("Split outputs:"))
        #expect(splitOutput.contains("arm64"))
        #expect(splitOutput.contains("x86_64"))
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

    @Test("build-xcframework creates an xcframework from static libraries")
    func buildXCFrameworkCreatesOutput() throws {
        let fixture = try makeXCFrameworkFixture()
        let outputURL = fixture.directory.appendingPathComponent("libWeiboSDK.xcframework")

        let output = try runCLI(arguments: [
            "build-xcframework",
            "--library", fixture.deviceLibraryURL.path,
            "--library", fixture.simulatorLibraryURL.path,
            "--headers", fixture.headersDirectoryURL.path,
            "--output", outputURL.path,
        ])

        #expect(output.contains("XCFramework output: \(outputURL.path)"))
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        #expect(FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("Info.plist").path))
    }

    @Test("build-xcframework advanced mode retags and packages maccatalyst slices")
    func buildXCFrameworkAdvancedModeCreatesCatalystSlice() throws {
        let fixture = try makeXCFrameworkFixture()
        let outputURL = fixture.directory.appendingPathComponent("libWeiboSDK-advanced.xcframework")

        let output = try runCLI(arguments: [
            "build-xcframework",
            "--source-library", fixture.deviceLibraryURL.path,
            "--ios-simulator-source-library", fixture.simulatorLibraryURL.path,
            "--headers-dir", fixture.headersDirectoryURL.path,
            "--output", outputURL.path,
            "--output-library-name", "libWeiboSDK.a",
            "--maccatalyst-min-version", "14.0",
            "--maccatalyst-sdk-version", "14.4.0",
        ])

        #expect(output.contains("XCFramework output: \(outputURL.path)"))

        let infoPlistData = try Data(contentsOf: outputURL.appendingPathComponent("Info.plist"))
        let plist = try #require(
            PropertyListSerialization.propertyList(from: infoPlistData, format: nil) as? [String: Any]
        )
        let libraries = try #require(plist["AvailableLibraries"] as? [[String: Any]])

        #expect(libraries.contains { library in
            (library["SupportedPlatform"] as? String) == "ios" &&
            (library["SupportedPlatformVariant"] as? String) == "maccatalyst"
        })
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
        #expect(validateOutput.contains("Validation: OK"))
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

    private func runCLI(arguments: [String], expectedStatus: Int32 = 0) throws -> String {
        let cliURL = try cliProductURL()
        #expect(FileManager.default.isExecutableFile(atPath: cliURL.path), "machoe-cli executable should exist at \(cliURL.path)")

        let process = Process()
        process.executableURL = cliURL
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        // Read before waiting so large outputs cannot fill the pipe and deadlock the child.
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: outputData, encoding: .utf8) ?? ""

        #expect(
            process.terminationStatus == expectedStatus,
            "CLI exited with status \(process.terminationStatus) (expected \(expectedStatus)): \(output)"
        )
        return output
    }

    private func projectMarketingVersion() throws -> String {
        let projectURL = repoRoot()
            .appendingPathComponent("MachOKnife.xcodeproj")
            .appendingPathComponent("project.pbxproj")
        let contents = try String(contentsOf: projectURL, encoding: .utf8)
        guard let range = contents.range(of: #"MARKETING_VERSION = ([^;]+);"#, options: .regularExpression) else {
            throw CLITestError.fixtureNotFound("MARKETING_VERSION in \(projectURL.path)")
        }
        return contents[range]
            .replacingOccurrences(of: "MARKETING_VERSION = ", with: "")
            .replacingOccurrences(of: ";", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    }

    private func cliProductURL() throws -> URL {
        let productsDirectory = try productsDirectory()
        return productsDirectory.appendingPathComponent("machoe-cli")
    }

    private func makeFatArchiveFixture() throws -> ArchiveFixture {
        let directory = try makeTemporaryDirectory()
        let sourceURL = directory.appendingPathComponent("archive-fixture.c")
        let arm64ObjectURL = directory.appendingPathComponent("archive-fixture-arm64.o")
        let x86ObjectURL = directory.appendingPathComponent("archive-fixture-x86_64.o")
        let arm64ArchiveURL = directory.appendingPathComponent("libArchiveFixture-arm64.a")
        let x86ArchiveURL = directory.appendingPathComponent("libArchiveFixture-x86_64.a")
        let fatArchiveURL = directory.appendingPathComponent("libArchiveFixture-fat.a")

        try "int archive_fixture_symbol(void) { return 2; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        try runTool(
            "/usr/bin/clang",
            arguments: [
                "-target", "arm64-apple-ios11.0",
                "-c",
                sourceURL.path,
                "-o",
                arm64ObjectURL.path,
            ]
        )
        try runTool(
            "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-ios11.0-simulator",
                "-c",
                sourceURL.path,
                "-o",
                x86ObjectURL.path,
            ]
        )
        try runTool(
            "/usr/bin/libtool",
            arguments: [
                "-static",
                "-o",
                arm64ArchiveURL.path,
                arm64ObjectURL.path,
            ]
        )
        try runTool(
            "/usr/bin/libtool",
            arguments: [
                "-static",
                "-o",
                x86ArchiveURL.path,
                x86ObjectURL.path,
            ]
        )
        try runTool(
            "/usr/bin/lipo",
            arguments: [
                "-create",
                arm64ArchiveURL.path,
                x86ArchiveURL.path,
                "-output",
                fatArchiveURL.path,
            ]
        )

        return ArchiveFixture(
            directory: directory,
            arm64ArchiveURL: arm64ArchiveURL,
            x86ArchiveURL: x86ArchiveURL,
            archiveURL: fatArchiveURL
        )
    }

    private func makeXCFrameworkFixture() throws -> XCFrameworkFixture {
        let directory = try makeTemporaryDirectory()
        let headersDirectoryURL = directory.appendingPathComponent("Headers", isDirectory: true)
        let sourceURL = directory.appendingPathComponent("weibo-fixture.c")
        let headerURL = headersDirectoryURL.appendingPathComponent("WeiboSDK.h")
        let arm64ObjectURL = directory.appendingPathComponent("weibo-fixture-arm64.o")
        let x86ObjectURL = directory.appendingPathComponent("weibo-fixture-x86_64.o")
        let deviceLibraryURL = directory.appendingPathComponent("libWeiboSDK-arm64.a")
        let simulatorLibraryURL = directory.appendingPathComponent("libWeiboSDK-x86_64.a")

        try FileManager.default.createDirectory(at: headersDirectoryURL, withIntermediateDirectories: true)
        try """
        #ifndef WEIBO_SDK_H
        #define WEIBO_SDK_H
        int weibo_fixture_symbol(void);
        #endif
        """.write(to: headerURL, atomically: true, encoding: .utf8)
        try "#include \"WeiboSDK.h\"\nint weibo_fixture_symbol(void) { return 7; }\n".write(
            to: sourceURL,
            atomically: true,
            encoding: .utf8
        )

        try runTool(
            "/usr/bin/clang",
            arguments: [
                "-target", "arm64-apple-ios14.0",
                "-I", headersDirectoryURL.path,
                "-c",
                sourceURL.path,
                "-o",
                arm64ObjectURL.path,
            ]
        )
        try runTool(
            "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-ios14.0-simulator",
                "-I", headersDirectoryURL.path,
                "-c",
                sourceURL.path,
                "-o",
                x86ObjectURL.path,
            ]
        )
        try runTool(
            "/usr/bin/libtool",
            arguments: [
                "-static",
                "-o",
                deviceLibraryURL.path,
                arm64ObjectURL.path,
            ]
        )
        try runTool(
            "/usr/bin/libtool",
            arguments: [
                "-static",
                "-o",
                simulatorLibraryURL.path,
                x86ObjectURL.path,
            ]
        )

        return XCFrameworkFixture(
            directory: directory,
            deviceLibraryURL: deviceLibraryURL,
            simulatorLibraryURL: simulatorLibraryURL,
            headersDirectoryURL: headersDirectoryURL
        )
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

    private func runTool(_ launchPath: String, arguments: [String]) throws {
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
            Issue.record("Command failed: \(launchPath) \(arguments.joined(separator: " "))\n\(output)")
            throw CLITestError.fixtureNotFound("failed to build fat archive fixture")
        }
    }
}

private final class BundleProbe: NSObject {}

private enum CLITestError: Error {
    case productsDirectoryNotFound
    case fixtureNotFound(String)
}

    private struct ArchiveFixture {
        let directory: URL
        let arm64ArchiveURL: URL
        let x86ArchiveURL: URL
        let archiveURL: URL
    }

private struct XCFrameworkFixture {
    let directory: URL
    let deviceLibraryURL: URL
    let simulatorLibraryURL: URL
    let headersDirectoryURL: URL
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

/// Fat slices are listed in file order (as lipo wrote them), so compare architectures as a set.
private func architectureList(in output: String) -> [String] {
    guard let line = output.split(separator: "\n").first(where: { $0.hasPrefix("Architectures: ") }) else {
        return []
    }
    return line.dropFirst("Architectures: ".count)
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .sorted()
}

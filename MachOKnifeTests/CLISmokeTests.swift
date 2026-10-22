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

    // 使用仓库内固定的 CLI 夹具，而不是只在 Debug + ENABLE_DEBUG_DYLIB 构建下才存在的 MachOKnife.debug.dylib，
    // 这样断言的值是确定的，不随应用构建配置变化。
    @Test("info prints slice summaries")
    func infoPrintsSliceSummaries() throws {
        let fixtureURL = try cliEditableFixtureURL()
        let output = try runCLI(arguments: ["info", fixtureURL.path])

        #expect(output.contains("Slices: 1"))
        #expect(output.contains("Architecture: x86_64"))
        #expect(output.contains("File Type: dylib"))
        #expect(output.contains("Platform: macOS"))
        #expect(output.contains("Install Name: @rpath/libCLIEditable.dylib"))
        #expect(output.contains("Code Signature: present"))
    }

    @Test("list-dylibs prints dylib and rpath entries")
    func listDylibsPrintsDylibAndRPathEntries() throws {
        let fixtureURL = try cliEditableFixtureURL()
        let output = try runCLI(arguments: ["list-dylibs", fixtureURL.path])

        #expect(output.contains("ID: @rpath/libCLIEditable.dylib"))
        #expect(output.contains("DYLIB @rpath/libCLIDependency.dylib"))
        #expect(output.contains("DYLIB /usr/lib/libSystem.B.dylib"))
        #expect(output.contains("RPATH @loader_path/Frameworks"))
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

        let splitPaths = splitOutput.split(separator: "\n").dropFirst().map(String.init)

        #expect(mergeOutput.contains("Merged output: \(mergedArchiveURL.path)"))
        #expect(FileManager.default.fileExists(atPath: mergedArchiveURL.path))
        #expect(splitOutput.hasPrefix("Split outputs:"))
        // 原断言只检查文本包含架构名；这里确认每个拆分产物都真实存在且只含对应架构。
        #expect(splitPaths.count == 2)
        for path in splitPaths {
            #expect(FileManager.default.fileExists(atPath: path))
            let expectedArchitecture = path.contains("-arm64") ? "arm64" : "x86_64"
            let infoOutput = try runCLI(arguments: ["info", path])
            #expect(architectureList(in: infoOutput) == [expectedArchitecture])
        }
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

    // MARK: - 输出流与退出码约定

    @Test("errors are written to stderr and leave stdout empty")
    func errorsAreWrittenToStandardError() throws {
        let unsupported = try runCLIStreams(arguments: ["bogus-command"], expectedStatus: 64)
        #expect(unsupported.standardOutput.isEmpty)
        #expect(unsupported.standardError.contains("error: unsupported command 'bogus-command'"))

        let fixtureURL = try cliEditableFixtureURL()
        let unknownOption = try runCLIStreams(arguments: ["summary", fixtureURL.path, "--bogus"], expectedStatus: 64)
        #expect(unknownOption.standardOutput.isEmpty)
        #expect(unknownOption.standardError.contains("unknown option '--bogus'"))
    }

    @Test("a failing check still writes its report to stdout")
    func failingCheckWritesReportToStandardOutput() throws {
        let fixture = try makeFatArchiveFixture()

        let result = try runCLIStreams(arguments: [
            "check-contamination", fixture.archiveURL.path,
            "--mode", "architecture",
            "--target", "arm64",
        ], expectedStatus: 1)

        #expect(result.standardOutput.contains("Mismatches"))
        #expect(result.standardError.isEmpty)
    }

    @Test("help and --help print to stdout and exit successfully")
    func helpPrintsToStandardOutput() throws {
        let result = try runCLIStreams(arguments: ["help", "set-id"])

        #expect(result.standardOutput.contains("set-id: Change the install name of a dylib."))
        #expect(result.standardError.isEmpty)
    }

    @Test("help for an unknown command is a usage error")
    func helpForUnknownCommandIsUsageError() throws {
        let result = try runCLIStreams(arguments: ["help", "bogus"], expectedStatus: 64)

        #expect(result.standardError.contains("unsupported command 'bogus'"))
    }

    // 回归测试：version / help 的多余参数以前被静默忽略。
    @Test("version and help reject extra arguments")
    func versionAndHelpRejectExtraArguments() throws {
        let version = try runCLIStreams(arguments: ["--version", "extra"], expectedStatus: 64)
        #expect(version.standardError.contains("unexpected argument 'extra'"))

        let help = try runCLIStreams(arguments: ["help", "info", "extra"], expectedStatus: 64)
        #expect(help.standardError.contains("unexpected argument 'extra'"))
    }

    // 回归测试：非 Mach-O 输入以前只会得到 "(CoreMachO.MachOParseError error 0.)" 这种无法理解的错误。
    @Test("non-Mach-O input produces a readable error")
    func nonMachOInputProducesReadableError() throws {
        let textURL = try makeTemporaryDirectory().appendingPathComponent("notes.txt")
        try "definitely not a Mach-O file\n".write(to: textURL, atomically: true, encoding: .utf8)

        for command in ["info", "validate", "list-dylibs"] {
            let result = try runCLIStreams(arguments: [command, textURL.path], expectedStatus: 1)
            #expect(result.standardError.contains("not a Mach-O file"), "\(command): \(result.standardError)")
            #expect(result.standardError.contains("MachOParseError error") == false)
        }
    }

    @Test("a missing input file is reported on stderr with exit status 1")
    func missingInputFileIsReported() throws {
        let missingURL = try makeTemporaryDirectory().appendingPathComponent("missing.dylib")

        let result = try runCLIStreams(arguments: ["summary", missingURL.path], expectedStatus: 1)

        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.hasPrefix("error: "))
    }

    // MARK: - 参数解析

    @Test("missing option values and missing required options are usage errors")
    func missingOptionValuesAreUsageErrors() throws {
        let fixtureURL = try cliEditableFixtureURL()

        let missingValue = try runCLIStreams(arguments: ["set-id", fixtureURL.path, "--output"], expectedStatus: 64)
        #expect(missingValue.standardError.contains("option '--output' requires a value"))

        let neverWrittenURL = try makeTemporaryDirectory().appendingPathComponent("never-written.dylib")
        let missingOption = try runCLIStreams(arguments: ["set-id", fixtureURL.path, "--output", neverWrittenURL.path], expectedStatus: 64)
        #expect(missingOption.standardError.contains("missing required option '--install-name'"))
        #expect(FileManager.default.fileExists(atPath: neverWrittenURL.path) == false)

        let missingPath = try runCLIStreams(arguments: ["info"], expectedStatus: 64)
        #expect(missingPath.standardError.contains("missing input path"))

        let extraPath = try runCLIStreams(arguments: ["info", fixtureURL.path, fixtureURL.path], expectedStatus: 64)
        #expect(extraPath.standardError.contains("unexpected argument"))
    }

    // 回归测试：重复的单值选项以前会静默取第一个值。
    @Test("repeating a single-value option is rejected before anything is written")
    func repeatedSingleValueOptionIsRejected() throws {
        let fixtureURL = try cliEditableFixtureURL()
        let outputURL = try makeTemporaryDirectory().appendingPathComponent("set-id.dylib")

        let result = try runCLIStreams(arguments: [
            "set-id", fixtureURL.path,
            "--install-name", "@rpath/first.dylib",
            "--install-name", "@rpath/second.dylib",
            "--output", outputURL.path,
        ], expectedStatus: 64)

        #expect(result.standardError.contains("option '--install-name' may only be specified once"))
        #expect(FileManager.default.fileExists(atPath: outputURL.path) == false)
    }

    @Test("--name=value syntax and the -- terminator are supported")
    func inlineOptionValuesAndTerminatorAreSupported() throws {
        let fixtureURL = try cliEditableFixtureURL()
        let outputURL = try makeTemporaryDirectory().appendingPathComponent("inline.dylib")

        _ = try runCLI(arguments: [
            "set-id",
            "--install-name=@rpath/libInline.dylib",
            "--output=\(outputURL.path)",
            "--", fixtureURL.path,
        ])
        let infoOutput = try runCLI(arguments: ["info", "--", outputURL.path])

        #expect(infoOutput.contains("Install Name: @rpath/libInline.dylib"))
    }

    // MARK: - info --json

    @Test("info --json emits machine-readable slice metadata")
    func infoJSONEmitsSliceMetadata() throws {
        let fixtureURL = try cliEditableFixtureURL()

        let result = try runCLIStreams(arguments: ["info", fixtureURL.path, "--json"])
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any]
        )
        let slices = try #require(object["slices"] as? [[String: Any]])
        let slice = try #require(slices.first)
        let dylibs = try #require(slice["dylibs"] as? [[String: Any]])

        #expect(object["file"] as? String == fixtureURL.path)
        #expect(object["container"] as? String == "thin")
        #expect(slices.count == 1)
        #expect(slice["architecture"] as? String == "x86_64")
        #expect(slice["fileType"] as? String == "dylib")
        #expect(slice["platform"] as? String == "macOS")
        #expect(slice["installName"] as? String == "@rpath/libCLIEditable.dylib")
        #expect(slice["codeSignature"] as? Bool == true)
        #expect(slice["rpaths"] as? [String] == ["@loader_path/Frameworks"])
        #expect(dylibs.compactMap { $0["path"] as? String }.contains("@rpath/libCLIDependency.dylib"))
        #expect(dylibs.allSatisfy { ($0["kind"] as? String) == "load" })
        #expect(result.standardError.isEmpty)
    }

    @Test("info --json reports archive architectures")
    func infoJSONReportsArchiveArchitectures() throws {
        let fixture = try makeFatArchiveFixture()

        let output = try runCLI(arguments: ["info", "--json", fixture.archiveURL.path])
        let object = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        let architectures = try #require(object["architectures"] as? [[String: Any]])

        #expect(object["container"] as? String == "fat archive")
        #expect(architectures.compactMap { $0["architecture"] as? String }.sorted() == ["arm64", "x86_64"])
        #expect(architectures.allSatisfy { ($0["members"] as? Int) == 1 })
    }

    // MARK: - 输出安全

    // 回归测试：merge 的输出等于某个输入时，服务层会先删除输出（即该输入）再调用 lipo，导致输入永久丢失。
    @Test("merge refuses to overwrite one of its inputs")
    func mergeRefusesToOverwriteAnInput() throws {
        let fixture = try makeFatArchiveFixture()
        let originalData = try Data(contentsOf: fixture.arm64ArchiveURL)
        // 用带 `..` 的写法指向同一文件，确认比较前做了路径标准化。
        let aliasedOutputPath = fixture.directory
            .appendingPathComponent("subdir")
            .path + "/../" + fixture.arm64ArchiveURL.lastPathComponent

        let result = try runCLIStreams(arguments: [
            "merge",
            fixture.arm64ArchiveURL.path,
            fixture.x86ArchiveURL.path,
            "--output", aliasedOutputPath,
        ], expectedStatus: 64)

        #expect(result.standardError.contains("must not overwrite an input file"))
        #expect(try Data(contentsOf: fixture.arm64ArchiveURL) == originalData)
    }

    @Test("merge with a single input is a usage error")
    func mergeWithSingleInputIsUsageError() throws {
        let fixture = try makeFatArchiveFixture()
        let outputURL = fixture.directory.appendingPathComponent("Merged.a")

        let result = try runCLIStreams(arguments: [
            "merge", fixture.arm64ArchiveURL.path, "--output", outputURL.path,
        ], expectedStatus: 64)

        #expect(result.standardError.contains("expected at least 2 input path(s)"))
        #expect(FileManager.default.fileExists(atPath: outputURL.path) == false)
    }

    @Test("split exports each requested architecture once and rejects unknown ones")
    func splitHandlesRequestedArchitectures() throws {
        let fixture = try makeFatArchiveFixture()
        let outputDirectory = fixture.directory.appendingPathComponent("split", isDirectory: true)

        let output = try runCLI(arguments: [
            "split", fixture.archiveURL.path,
            "--output-dir", outputDirectory.path,
            "--arch", "arm64",
            "--arch", "arm64",
        ])
        let outputPaths = output.split(separator: "\n").dropFirst()

        #expect(outputPaths.count == 1)
        #expect(outputPaths.first?.hasSuffix("-arm64.a") == true)

        let missing = try runCLIStreams(arguments: [
            "split", fixture.archiveURL.path,
            "--output-dir", outputDirectory.path,
            "--arch", "riscv",
        ], expectedStatus: 1)
        #expect(missing.standardError.contains("riscv"))
    }

    // 回归测试：`--output` 与 `--output-dir` 同时出现时，以前会静默忽略 `--output-dir`。
    @Test("build-xcframework rejects --output combined with --output-dir")
    func buildXCFrameworkRejectsConflictingOutputs() throws {
        let fixture = try makeXCFrameworkFixture()

        let result = try runCLIStreams(arguments: [
            "build-xcframework",
            "--source-library", fixture.deviceLibraryURL.path,
            "--headers-dir", fixture.headersDirectoryURL.path,
            "--output", fixture.directory.appendingPathComponent("A.xcframework").path,
            "--output-dir", fixture.directory.path,
        ], expectedStatus: 64)

        #expect(result.standardError.contains("--output cannot be combined with --output-dir"))
    }

    // 回归测试：简单模式以前在 xcodebuild 运行前就删除已有的 xcframework，构建失败时旧产物丢失。
    @Test("build-xcframework keeps the previous bundle when the build fails")
    func buildXCFrameworkKeepsPreviousBundleOnFailure() throws {
        let fixture = try makeXCFrameworkFixture()
        let outputURL = fixture.directory.appendingPathComponent("Existing.xcframework", isDirectory: true)
        let markerURL = outputURL.appendingPathComponent("marker.txt")
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        try "previous build".write(to: markerURL, atomically: true, encoding: .utf8)
        let bogusLibraryURL = fixture.directory.appendingPathComponent("libBogus.a")
        try "not a library".write(to: bogusLibraryURL, atomically: true, encoding: .utf8)

        _ = try runCLIStreams(arguments: [
            "build-xcframework",
            "--library", bogusLibraryURL.path,
            "--headers", fixture.headersDirectoryURL.path,
            "--output", outputURL.path,
        ], expectedStatus: 1)

        #expect(FileManager.default.fileExists(atPath: markerURL.path))
    }

    @Test("validate exits with status 1 for a non-Mach-O file")
    func validateFailsForNonMachOFile() throws {
        let textURL = try makeTemporaryDirectory().appendingPathComponent("notes.bin")
        try Data(repeating: 0, count: 64).write(to: textURL)

        let result = try runCLIStreams(arguments: ["validate", textURL.path], expectedStatus: 1)

        #expect(result.standardError.hasPrefix("error: "))
    }

    // MARK: - remove-arch

    @Test("remove-arch strips architectures from a fat dylib")
    func removeArchStripsArchitecturesFromFatDylib() throws {
        let fixture = try makeFatDylibFixture()
        let outputURL = fixture.directory.appendingPathComponent("libFat-arm64.dylib")
        let originalData = try Data(contentsOf: fixture.fatDylibURL)

        let output = try runCLI(arguments: [
            "remove-arch", fixture.fatDylibURL.path,
            "--arch", "x86_64",
            "--output", outputURL.path,
        ])

        #expect(output.contains("Removed: x86_64"))
        #expect(output.contains("Remaining: arm64"))
        #expect(output.contains("Wrote: \(outputURL.path)"))
        // 用系统 lipo 独立确认输出只剩 arm64，且输入文件保持不变。
        #expect(try lipoArchitectures(of: outputURL) == ["arm64"])
        #expect(try Data(contentsOf: fixture.fatDylibURL) == originalData)
    }

    @Test("remove-arch strips architectures from a fat static library")
    func removeArchStripsArchitecturesFromFatArchive() throws {
        let fixture = try makeFatArchiveFixture()
        let outputURL = fixture.directory.appendingPathComponent("libArchiveFixture-device.a")

        _ = try runCLI(arguments: [
            "remove-arch", fixture.archiveURL.path,
            "--arch", "x86_64",
            "--output", outputURL.path,
        ])

        #expect(try lipoArchitectures(of: outputURL) == ["arm64"])
    }

    @Test("remove-arch --in-place rewrites the input file")
    func removeArchInPlaceRewritesInput() throws {
        let fixture = try makeFatDylibFixture()

        _ = try runCLI(arguments: [
            "remove-arch", fixture.fatDylibURL.path, "--arch", "arm64", "--in-place",
        ])

        #expect(try lipoArchitectures(of: fixture.fatDylibURL) == ["x86_64"])
    }

    @Test("remove-arch requires --output or --in-place and refuses to overwrite the input via --output")
    func removeArchOutputRules() throws {
        let fixture = try makeFatDylibFixture()
        let originalData = try Data(contentsOf: fixture.fatDylibURL)

        let missingOutput = try runCLIStreams(arguments: [
            "remove-arch", fixture.fatDylibURL.path, "--arch", "x86_64",
        ], expectedStatus: 64)
        #expect(missingOutput.standardError.contains("--in-place"))

        let sameAsInput = try runCLIStreams(arguments: [
            "remove-arch", fixture.fatDylibURL.path, "--arch", "x86_64", "--output", fixture.fatDylibURL.path,
        ], expectedStatus: 64)
        #expect(sameAsInput.standardError.contains("must not overwrite the input file"))

        let conflicting = try runCLIStreams(arguments: [
            "remove-arch", fixture.fatDylibURL.path, "--arch", "x86_64",
            "--output", fixture.directory.appendingPathComponent("out.dylib").path, "--in-place",
        ], expectedStatus: 64)
        #expect(conflicting.standardError.contains("--output cannot be combined with --in-place"))

        let missingArch = try runCLIStreams(arguments: [
            "remove-arch", fixture.fatDylibURL.path, "--in-place",
        ], expectedStatus: 64)
        #expect(missingArch.standardError.contains("missing required option '--arch'"))

        #expect(try Data(contentsOf: fixture.fatDylibURL) == originalData)
    }

    @Test("remove-arch rejects thin inputs, unknown architectures, and removing every architecture")
    func removeArchRejectsInvalidRequests() throws {
        let fixture = try makeFatDylibFixture()
        let outputURL = fixture.directory.appendingPathComponent("out.dylib")

        let thin = try runCLIStreams(arguments: [
            "remove-arch", fixture.arm64DylibURL.path, "--arch", "arm64", "--output", outputURL.path,
        ], expectedStatus: 1)
        #expect(thin.standardError.hasPrefix("error: "))

        let unknown = try runCLIStreams(arguments: [
            "remove-arch", fixture.fatDylibURL.path, "--arch", "riscv", "--output", outputURL.path,
        ], expectedStatus: 1)
        #expect(unknown.standardError.contains("riscv"))

        let all = try runCLIStreams(arguments: [
            "remove-arch", fixture.fatDylibURL.path,
            "--arch", "arm64", "--arch", "x86_64",
            "--output", outputURL.path,
        ], expectedStatus: 1)
        #expect(all.standardError.hasPrefix("error: "))

        // 任何失败都不应留下输出文件。
        #expect(FileManager.default.fileExists(atPath: outputURL.path) == false)
    }

    // MARK: - summary / check-contamination / list-dylibs --json

    @Test("summary --json emits the report as JSON")
    func summaryJSONEmitsReport() throws {
        let fixture = try makeFatArchiveFixture()

        let result = try runCLIStreams(arguments: ["summary", fixture.archiveURL.path, "--json"])
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any]
        )
        let summary = try #require(object["summary"] as? [String])
        let sections = try #require(object["sections"] as? [[String: Any]])

        #expect((object["title"] as? String)?.isEmpty == false)
        #expect(summary.contains("Kind: Fat Archive"))
        #expect(summary.contains { $0.hasPrefix("Architectures: ") && $0.contains("arm64") && $0.contains("x86_64") })
        #expect(sections.allSatisfy { $0["title"] is String && $0["lines"] is [String] })
        #expect(result.standardError.isEmpty)
    }

    @Test("check-contamination --json reports counts and keeps the mismatch exit status")
    func checkContaminationJSONKeepsExitStatus() throws {
        let fixture = try makeFatArchiveFixture()

        let mismatch = try runCLIStreams(arguments: [
            "check-contamination", fixture.archiveURL.path,
            "--mode", "architecture", "--target", "arm64", "--json",
        ], expectedStatus: 1)
        let mismatchObject = try #require(
            JSONSerialization.jsonObject(with: Data(mismatch.standardOutput.utf8)) as? [String: Any]
        )
        #expect(mismatchObject["mode"] as? String == "architecture")
        #expect(mismatchObject["target"] as? String == "arm64")
        #expect((mismatchObject["mismatchCount"] as? Int ?? 0) > 0)
        #expect(mismatchObject["report"] is [String: Any])

        let clean = try runCLIStreams(arguments: [
            "check-contamination", fixture.arm64ArchiveURL.path,
            "--mode", "architecture", "--target", "arm64", "--json",
        ])
        let cleanObject = try #require(
            JSONSerialization.jsonObject(with: Data(clean.standardOutput.utf8)) as? [String: Any]
        )
        #expect(cleanObject["mismatchCount"] as? Int == 0)
        #expect((cleanObject["okCount"] as? Int ?? 0) > 0)
    }

    @Test("list-dylibs --json emits dylib and rpath entries")
    func listDylibsJSONEmitsEntries() throws {
        let fixtureURL = try cliEditableFixtureURL()

        let output = try runCLIStreams(arguments: ["list-dylibs", "--json", fixtureURL.path]).standardOutput
        let object = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        let slices = try #require(object["slices"] as? [[String: Any]])
        let slice = try #require(slices.first)
        let dylibs = try #require(slice["dylibs"] as? [[String: Any]])

        #expect(object["file"] as? String == fixtureURL.path)
        #expect(slice["architecture"] as? String == "x86_64")
        #expect(slice["installName"] as? String == "@rpath/libCLIEditable.dylib")
        #expect(slice["rpaths"] as? [String] == ["@loader_path/Frameworks"])
        #expect(dylibs.compactMap { $0["path"] as? String }.contains("/usr/lib/libSystem.B.dylib"))

        let archiveFixture = try makeFatArchiveFixture()
        let archiveOutput = try runCLI(arguments: ["list-dylibs", archiveFixture.archiveURL.path, "--json"])
        let archiveObject = try #require(JSONSerialization.jsonObject(with: Data(archiveOutput.utf8)) as? [String: Any])
        let architectures = try #require(archiveObject["architectures"] as? [[String: Any]])
        #expect(architectures.compactMap { $0["architecture"] as? String }.sorted() == ["arm64", "x86_64"])
    }

    /// 运行 CLI 并返回 stdout + stderr 的合并文本（便于只关心内容的用例）。
    private func runCLI(arguments: [String], expectedStatus: Int32 = 0) throws -> String {
        let result = try runCLIStreams(arguments: arguments, expectedStatus: expectedStatus)
        return result.standardOutput + result.standardError
    }

    /// 运行 CLI 并分别返回 stdout 与 stderr，用于验证“报告写 stdout、错误写 stderr”的约定。
    private func runCLIStreams(arguments: [String], expectedStatus: Int32 = 0) throws -> CLIRunResult {
        let cliURL = try cliProductURL()
        #expect(FileManager.default.isExecutableFile(atPath: cliURL.path), "machoe-cli executable should exist at \(cliURL.path)")

        let process = Process()
        process.executableURL = cliURL
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        // 两个管道需要同时读取：先读完一个再读另一个时，子进程可能因另一个管道写满而阻塞，造成死锁。
        let errorCollector = PipeCollector(handle: errorPipe.fileHandleForReading)
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorCollector.wait()
        process.waitUntilExit()

        let result = CLIRunResult(
            standardOutput: String(data: outputData, encoding: .utf8) ?? "",
            standardError: String(data: errorData, encoding: .utf8) ?? "",
            status: process.terminationStatus
        )

        #expect(
            result.status == expectedStatus,
            "CLI exited with status \(result.status) (expected \(expectedStatus)): \(result.standardOutput)\(result.standardError)"
        )
        return result
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

    /// 构建 arm64 + x86_64 的通用 macOS dylib 夹具，供 remove-arch 用例使用。
    private func makeFatDylibFixture() throws -> FatDylibFixture {
        let directory = try makeTemporaryDirectory()
        let sourceURL = directory.appendingPathComponent("fat-fixture.c")
        let arm64DylibURL = directory.appendingPathComponent("libFat-arm64-thin.dylib")
        let x86DylibURL = directory.appendingPathComponent("libFat-x86_64-thin.dylib")
        let fatDylibURL = directory.appendingPathComponent("libFat.dylib")

        try "int fat_fixture_symbol(void) { return 3; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        for (target, outputURL) in [("arm64-apple-macos11.0", arm64DylibURL), ("x86_64-apple-macos11.0", x86DylibURL)] {
            try runTool(
                "/usr/bin/clang",
                arguments: [
                    "-target", target,
                    "-dynamiclib",
                    "-install_name", "@rpath/libFat.dylib",
                    sourceURL.path,
                    "-o",
                    outputURL.path,
                ]
            )
        }
        try runTool(
            "/usr/bin/lipo",
            arguments: ["-create", arm64DylibURL.path, x86DylibURL.path, "-output", fatDylibURL.path]
        )

        return FatDylibFixture(directory: directory, arm64DylibURL: arm64DylibURL, fatDylibURL: fatDylibURL)
    }

    /// 用系统 `lipo -archs` 读取文件包含的架构（排序后返回），独立于被测 CLI 校验结果。
    private func lipoArchitectures(of url: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/lipo")
        process.arguments = ["-archs", url.path]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        try process.run()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "lipo -archs failed for \(url.path)")
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map(String.init)
            .sorted()
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
        // 先并发读完两个管道再等待退出，避免工具输出写满管道缓冲后与 waitUntilExit 互相等待。
        let errorCollector = PipeCollector(handle: errorPipe.fileHandleForReading)
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorCollector.wait()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
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

private struct FatDylibFixture {
    let directory: URL
    let arm64DylibURL: URL
    let fatDylibURL: URL
}

private struct CLIRunResult {
    let standardOutput: String
    let standardError: String
    let status: Int32
}

/// 在后台线程读完一个管道，供同时读取 stdout / stderr 时使用。
private final class PipeCollector: @unchecked Sendable {
    private let group = DispatchGroup()
    private var data = Data()

    init(handle: FileHandle) {
        group.enter()
        DispatchQueue.global().async {
            self.data = handle.readDataToEndOfFile()
            self.group.leave()
        }
    }

    /// 阻塞直到管道读到 EOF，并返回读取到的全部数据（group 保证读写之间的可见性）。
    func wait() -> Data {
        group.wait()
        return data
    }
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

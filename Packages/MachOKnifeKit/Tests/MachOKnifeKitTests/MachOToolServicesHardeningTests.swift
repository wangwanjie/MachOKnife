import CoreMachO
import Foundation
import Testing
@testable import MachOKnifeKit

struct MachOToolServicesHardeningTests {
    @Test(
        "archive analysis counts members per architecture, keeps duplicate members and sorts versions numerically",
        arguments: [true, false]
    )
    func archiveAnalysisFiltersMembersPerArchitecture(thin: Bool) throws {
        let fixture = try ToolFixtureFactory.makeMixedArchive(thin: thin)

        let analysis = try #require(try ArchiveAnalysisService().analyze(url: fixture.archiveURL))
        let arm64 = try #require(analysis.architectures.first(where: { $0.architecture == "arm64" }))
        let x86 = try #require(analysis.architectures.first(where: { $0.architecture == "x86_64" }))

        #expect(analysis.kind == (thin ? .archive : .fatArchive))
        #expect(arm64.memberCount == 2)
        #expect(arm64.parsedMemberCount == 2)
        #expect(arm64.minimumOSVersions == ["9.0.0", "10.0.0"])
        #expect(x86.memberCount == 1)
        #expect(x86.minimumOSVersions == ["12.0.0"])
    }

    @Test("binary summary sorts versions numerically and counts members per architecture", arguments: [true, false])
    func binarySummarySortsVersionsNumerically(thin: Bool) throws {
        let fixture = try ToolFixtureFactory.makeMixedArchive(thin: thin)

        let report = try BinarySummaryService().makeReport(for: fixture.archiveURL)
        let arm64 = try #require(report.sections.first(where: { $0.title == "arm64" }))
        let x86 = try #require(report.sections.first(where: { $0.title == "x86_64" }))

        #expect(arm64.lines.contains("Members: 2"))
        #expect(arm64.lines.contains("Minimum OS: 9.0.0, 10.0.0"))
        #expect(x86.lines.contains("Members: 1"))
        #expect(x86.lines.contains("Minimum OS: 12.0.0"))
    }

    @Test("contamination check attributes archive members to their own architecture", arguments: [true, false])
    func contaminationCheckAttributesMembersToTheirArchitecture(thin: Bool) throws {
        let fixture = try ToolFixtureFactory.makeMixedArchive(thin: thin)

        let report = try BinaryContaminationCheckService().runCheck(
            at: fixture.archiveURL,
            target: "arm64",
            mode: .architecture
        )

        #expect(report.okCount == 2)
        #expect(report.mismatchCount == 1)
        #expect(report.uncheckedCount == 0)
    }

    @Test("numeric version sorting orders components as numbers")
    func numericVersionSorting() {
        #expect(numericallySortedVersions(["10.0.0", "9.0.0", "13.1.0", "9.0.0", "9.10.0", "9.2.0"])
            == ["9.0.0", "9.2.0", "9.10.0", "10.0.0", "13.1.0"])
        #expect(numericallySortedVersions(["unknown", "2.0", "1.5"]) == ["1.5", "2.0", "unknown"])
    }

    @Test("splitting a thin Mach-O copies the matching architecture")
    func splittingThinMachOCopiesMatchingArchitecture() throws {
        let fixture = try ToolFixtureFactory.makeThinDylib()
        let outputDirectory = fixture.directory.appendingPathComponent("split", isDirectory: true)

        let outputs = try MachOMergeSplitService().split(
            inputURL: fixture.binaryURL,
            architectures: ["x86_64"],
            outputDirectoryURL: outputDirectory
        )

        let output = try #require(outputs.first)
        #expect(outputs.count == 1)
        #expect(try Data(contentsOf: output) == Data(contentsOf: fixture.binaryURL))
    }

    @Test("splitting a thin Mach-O rejects architectures it does not contain")
    func splittingThinMachORejectsMissingArchitecture() throws {
        let fixture = try ToolFixtureFactory.makeThinDylib()
        let outputDirectory = fixture.directory.appendingPathComponent("split", isDirectory: true)

        #expect {
            try MachOMergeSplitService().split(
                inputURL: fixture.binaryURL,
                architectures: ["arm64"],
                outputDirectoryURL: outputDirectory
            )
        } throws: { error in
            guard case let .architectureNotFound(name, available) = error as? MachOToolServiceError else { return false }
            return name == "arm64" && available == ["x86_64"]
        }
    }

    @Test("process runner drains large stdout and stderr output without deadlocking")
    func processRunnerDrainsLargeOutput() throws {
        let result = try ToolProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 300000 /dev/zero >&2; head -c 300000 /dev/zero"]
        )

        #expect(result.succeeded)
        #expect(result.standardOutput.count == 300_000)
        #expect(result.standardError.count == 300_000)
    }

    @Test("developer roots keep their order, drop duplicates and never include the parent directory")
    func developerRootsAreOrderedAndDeduplicated() {
        let xcode = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer", isDirectory: true)
        let beta = URL(fileURLWithPath: "/Applications/Xcode-beta.app/Contents/Developer", isDirectory: true)

        #expect(XCFrameworkDeveloperToolLocator.orderedDeveloperRoots(selected: beta).map(\.path) == [beta.path, xcode.path])
        #expect(XCFrameworkDeveloperToolLocator.orderedDeveloperRoots(selected: xcode).map(\.path) == [xcode.path])
        #expect(XCFrameworkDeveloperToolLocator.orderedDeveloperRoots(selected: nil).map(\.path) == [xcode.path])
    }
}

struct XCFrameworkBuildScriptTests {
    @Test("prepare_headers writes a real module map inside Headers/<Module>")
    func prepareHeadersWritesModuleMapInsideModuleDirectory() throws {
        let directory = try ToolFixtureFactory.makeDirectory()
        // Distinct from "Headers" on case-insensitive volumes.
        let sourceHeaders = directory.appendingPathComponent("include", isDirectory: true)
        let outputHeaders = directory.appendingPathComponent("Headers", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceHeaders, withIntermediateDirectories: true)
        try "int a(void);\n".write(to: sourceHeaders.appendingPathComponent("A.h"), atomically: true, encoding: .utf8)
        try "int b(void);\n".write(to: sourceHeaders.appendingPathComponent("B.h"), atomically: true, encoding: .utf8)

        try ToolFixtureFactory.runBuildScriptFunction(
            in: directory,
            call: "prepare_headers(Path(sys.argv[1]), Path(sys.argv[2]), umbrella_header_name=None, module_name='MyKit')",
            arguments: [sourceHeaders.path, outputHeaders.path]
        )

        let moduleMap = try String(contentsOf: outputHeaders.appendingPathComponent("MyKit/module.modulemap"), encoding: .utf8)
        let umbrella = try String(contentsOf: outputHeaders.appendingPathComponent("MyKit/MyKit.h"), encoding: .utf8)

        #expect(moduleMap == "module MyKit {\n  umbrella header \"MyKit.h\"\n  export *\n}\n")
        #expect(umbrella == "#import <MyKit/A.h>\n#import <MyKit/B.h>\n")
        #expect(FileManager.default.fileExists(atPath: outputHeaders.appendingPathComponent("Modules").path) == false)
    }

    @Test("patch_object_platform clamps arm64 simulator retags to iOS 14 and copies non-Mach-O members")
    func patchObjectPlatformClampsSimulatorMinimumAndSkipsNonMachO() throws {
        let directory = try ToolFixtureFactory.makeDirectory()
        let objectURL = try ToolFixtureFactory.compileObject(
            in: directory,
            name: "device",
            target: "arm64-apple-ios11.0",
            body: "int device_symbol(void) { return 1; }"
        )
        let patchedURL = directory.appendingPathComponent("patched.o")
        let textURL = directory.appendingPathComponent("notes.txt")
        let copiedTextURL = directory.appendingPathComponent("notes-copy.txt")
        try "not a Mach-O".write(to: textURL, atomically: true, encoding: .utf8)

        let output = try ToolFixtureFactory.runBuildScriptFunction(
            in: directory,
            call: """
            print(patch_object_platform(Path(sys.argv[1]), Path(sys.argv[2]), target_platform=PLATFORM_IOSSIMULATOR, min_version_floor=ARM64_SIMULATOR_MIN_VERSION)); \
            print(patch_object_platform(Path(sys.argv[3]), Path(sys.argv[4]), target_platform=PLATFORM_IOSSIMULATOR))
            """,
            arguments: [objectURL.path, patchedURL.path, textURL.path, copiedTextURL.path]
        )

        let slice = try #require(try MachOContainer.parse(at: patchedURL).slices.first)
        let buildVersion = try #require(slice.buildVersion)
        #expect(output.split(whereSeparator: \.isNewline) == ["True", "False"])
        #expect(buildVersion.platform == .iOSSimulator)
        #expect(buildVersion.minimumOS == MachOVersion(major: 14, minor: 0, patch: 0))
        #expect(buildVersion.sdk >= buildVersion.minimumOS)
        #expect(try Data(contentsOf: copiedTextURL) == Data(contentsOf: textURL))
    }
}

struct ToolFixture {
    let directory: URL
    let archiveURL: URL
}

struct ToolBinaryFixture {
    let directory: URL
    let binaryURL: URL
}

enum ToolFixtureFactory {
    /// An archive holding two arm64 members named `dup.o` (iOS 10.0 and 9.0) and one x86_64 member.
    /// `thin` writes all three into one (non-fat) archive; otherwise `ar` produces a fat archive.
    static func makeMixedArchive(thin: Bool) throws -> ToolFixture {
        let directory = try makeDirectory()
        let first = try compileObject(
            in: directory.appendingPathComponent("first", isDirectory: true),
            name: "dup",
            target: "arm64-apple-ios10.0",
            body: "int dup_first(void) { return 1; }"
        )
        let second = try compileObject(
            in: directory.appendingPathComponent("second", isDirectory: true),
            name: "dup",
            target: "arm64-apple-ios9.0",
            body: "int dup_second(void) { return 2; }"
        )
        let x86 = try compileObject(
            in: directory,
            name: "intel",
            target: "x86_64-apple-ios12.0-simulator",
            body: "int intel_symbol(void) { return 3; }"
        )

        let archiveURL = directory.appendingPathComponent("libMixed.a")
        if thin {
            // `ar` splits mixed architectures into a fat archive, so write the thin archive directly.
            try ArchiveInspector().writeArchive(
                outputURL: archiveURL,
                members: [first, second, x86].map { ArchiveMemberSource(name: $0.lastPathComponent, fileURL: $0) },
                generateSymbolTable: false
            )
        } else {
            try run("/usr/bin/ar", arguments: ["-q", archiveURL.path, first.path, second.path, x86.path])
        }
        return ToolFixture(directory: directory, archiveURL: archiveURL)
    }

    static func makeThinDylib() throws -> ToolBinaryFixture {
        let directory = try makeDirectory()
        let sourceURL = directory.appendingPathComponent("thin.c")
        let binaryURL = directory.appendingPathComponent("libThin.dylib")
        try "int thin_symbol(void) { return 4; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try run("/usr/bin/clang", arguments: [
            "-target", "x86_64-apple-macos13.0", "-dynamiclib", sourceURL.path, "-o", binaryURL.path,
        ])
        return ToolBinaryFixture(directory: directory, binaryURL: binaryURL)
    }

    static func compileObject(in directory: URL, name: String, target: String, body: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("\(name).c")
        let objectURL = directory.appendingPathComponent("\(name).o")
        try "\(body)\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try run("/usr/bin/clang", arguments: ["-target", target, "-c", sourceURL.path, "-o", objectURL.path])
        return objectURL
    }

    /// Imports the embedded XCFramework build script as a module and runs `call` against it.
    @discardableResult
    static func runBuildScriptFunction(in directory: URL, call: String, arguments: [String]) throws -> String {
        let scriptURL = directory.appendingPathComponent("build_static_sdk_xcframework.py")
        try XCFrameworkBuildTool.scriptSource.write(to: scriptURL, atomically: true, encoding: .utf8)
        let driver = """
        import importlib.util, sys
        spec = importlib.util.spec_from_file_location("builder", sys.argv.pop(1))
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        globals().update({k: v for k, v in vars(builder).items() if not k.startswith("__")})
        \(call)
        """
        return try run("/usr/bin/python3", arguments: ["-c", driver, scriptURL.path] + arguments)
    }

    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    static func run(_ launchPath: String, arguments: [String]) throws -> String {
        let result = try ToolProcessRunner.run(executableURL: URL(fileURLWithPath: launchPath), arguments: arguments)
        guard result.succeeded else {
            throw ToolFixtureError.commandFailed(([launchPath] + arguments).joined(separator: " ") + "\n" + result.combinedOutputText)
        }
        return String(decoding: result.standardOutput, as: UTF8.self)
    }
}

enum ToolFixtureError: Error {
    case commandFailed(String)
}

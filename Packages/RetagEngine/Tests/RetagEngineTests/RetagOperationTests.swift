import Foundation
import Testing
@testable import RetagEngine
import CoreMachO

struct RetagOperationTests {
    @Test("platform retag preview returns diffs without mutating the source file")
    func platformRetagPreviewReturnsDiffsWithoutMutatingSourceFile() throws {
        let fixture = try RetagFixtureFactory.makeAbsolutePathFixture()
        let engine = RetagEngine()

        let preview = try engine.previewPlatformRetag(
            inputURL: fixture.binaryURL,
            platform: .macOS,
            minimumOS: MachOVersion(major: 14, minor: 0, patch: 0),
            sdk: MachOVersion(major: 14, minor: 4, patch: 0)
        )

        let original = try MachOContainer.parse(at: fixture.binaryURL)
        let buildVersion = try #require(original.slices.first?.buildVersion)

        #expect(preview.diff.entries.contains(where: { $0.kind == .platform }))
        #expect(buildVersion.minimumOS == MachOVersion(major: 13, minor: 0, patch: 0))
    }

    @Test("rewrite-dylib-paths replaces absolute dependency prefixes with @rpath")
    func rewriteDylibPathsReplacesAbsoluteDependencyPrefixesWithRPath() throws {
        let fixture = try RetagFixtureFactory.makeAbsolutePathFixture()
        let outputURL = fixture.directory.appendingPathComponent("rewritten-rpath.dylib")
        let engine = RetagEngine()

        let result = try engine.rewriteDylibPaths(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            fromPrefix: fixture.directory.path + "/",
            toPrefix: "@rpath/"
        )

        let container = try MachOContainer.parse(at: outputURL)
        let slice = try #require(container.slices.first)

        #expect(slice.dylibReferences.contains(where: { $0.path == "@rpath/libAbsoluteDependency.dylib" }))
        #expect(result.diff.entries.contains(where: { $0.kind == .dylib }))
    }

    @Test("fix-dyld-cache-dylib previews an @rpath install name and loader rpath")
    func fixDyldCacheDylibPreviewsRPathInstallNameAndLoaderRPath() throws {
        let fixture = try RetagFixtureFactory.makeDyldCacheStyleFixture()
        let engine = RetagEngine()

        let preview = try engine.previewFixDyldCacheDylib(inputURL: fixture.binaryURL)

        #expect(preview.diff.entries.contains(where: { $0.kind == .installName && $0.updatedValue == "@rpath/libCacheStyle.dylib" }))
        #expect(preview.diff.entries.contains(where: { $0.kind == .rpath && $0.updatedValue == "@loader_path" }))
        #expect(preview.diff.entries.contains(where: { $0.kind == .dylib && $0.updatedValue == "@rpath/libCacheDependency.dylib" }))
    }

    @Test("platform retag rewrites static archive members for mac catalyst")
    func platformRetagRewritesStaticArchiveMembersForMacCatalyst() throws {
        let fixture = try RetagFixtureFactory.makeVersionMinStaticArchiveFixture()
        let outputURL = fixture.directory.appendingPathComponent("rewritten-catalyst.a")
        let extractionDirectory = fixture.directory.appendingPathComponent("extracted", isDirectory: true)
        let engine = RetagEngine()

        let result = try engine.retagPlatform(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            platform: .macCatalyst,
            minimumOS: MachOVersion(major: 14, minor: 0, patch: 0),
            sdk: MachOVersion(major: 14, minor: 4, patch: 0)
        )

        try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        let memberName = try RetagShell.capture(
            launchPath: "/usr/bin/ar",
            arguments: ["-t", outputURL.path]
        )
        .split(separator: "\n")
        .map(String.init)
        .first(where: { $0.hasSuffix(".o") })
        .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let objectMember = try #require(memberName)

        try RetagShell.run(
            launchPath: "/usr/bin/ar",
            arguments: ["-x", outputURL.path, objectMember],
            currentDirectoryURL: extractionDirectory
        )

        let objectURL = extractionDirectory.appendingPathComponent(objectMember)
        let container = try MachOContainer.parse(at: objectURL)
        let slice = try #require(container.slices.first)
        let buildVersion = try #require(slice.buildVersion)

        #expect(result.diff.entries.contains(where: { $0.kind == .platform }))
        #expect(slice.versionMin == nil)
        #expect(buildVersion.platform == .macCatalyst)
        #expect(buildVersion.minimumOS == MachOVersion(major: 14, minor: 0, patch: 0))
        #expect(buildVersion.sdk == MachOVersion(major: 14, minor: 4, patch: 0))
    }

    @Test("platform retag requires an architecture for fat static archives")
    func platformRetagRequiresArchitectureForFatStaticArchives() throws {
        let fixture = try RetagFixtureFactory.makeFatVersionMinStaticArchiveFixture()
        let outputURL = fixture.directory.appendingPathComponent("rewritten-fat.a")
        let engine = RetagEngine()

        #expect(throws: ArchiveInspectorError.self) {
            try engine.retagPlatform(
                inputURL: fixture.binaryURL,
                outputURL: outputURL,
                platform: .macCatalyst,
                minimumOS: MachOVersion(major: 14, minor: 0, patch: 0),
                sdk: MachOVersion(major: 14, minor: 4, patch: 0)
            )
        }
    }

    @Test("platform retag rewrites the selected fat static archive architecture")
    func platformRetagRewritesSelectedFatStaticArchiveArchitecture() throws {
        let fixture = try RetagFixtureFactory.makeFatVersionMinStaticArchiveFixture()
        let outputURL = fixture.directory.appendingPathComponent("rewritten-fat-arm64.a")
        let extractionDirectory = fixture.directory.appendingPathComponent("fat-extracted", isDirectory: true)
        let engine = RetagEngine()

        let result = try engine.retagPlatform(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            platform: .macCatalyst,
            minimumOS: MachOVersion(major: 14, minor: 0, patch: 0),
            sdk: MachOVersion(major: 14, minor: 4, patch: 0),
            architecture: "arm64"
        )

        try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        let memberName = try RetagShell.capture(
            launchPath: "/usr/bin/ar",
            arguments: ["-t", outputURL.path]
        )
        .split(separator: "\n")
        .map(String.init)
        .first(where: { $0.hasSuffix(".o") })
        .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let objectMember = try #require(memberName)

        try RetagShell.run(
            launchPath: "/usr/bin/ar",
            arguments: ["-x", outputURL.path, objectMember],
            currentDirectoryURL: extractionDirectory
        )

        let objectURL = extractionDirectory.appendingPathComponent(objectMember)
        let container = try MachOContainer.parse(at: objectURL)
        let slice = try #require(container.slices.first)
        let buildVersion = try #require(slice.buildVersion)

        #expect(result.diff.entries.contains(where: { $0.kind == .platform }))
        #expect(slice.versionMin == nil)
        #expect(buildVersion.platform == .macCatalyst)
        #expect(buildVersion.minimumOS == MachOVersion(major: 14, minor: 0, patch: 0))
        #expect(buildVersion.sdk == MachOVersion(major: 14, minor: 4, patch: 0))
    }
}

private struct RetagFixture {
    let directory: URL
    let binaryURL: URL
}

private enum RetagFixtureFactory {
    static func makeAbsolutePathFixture() throws -> RetagFixture {
        let directory = try makeFixtureDirectory()
        let dependencySourceURL = directory.appendingPathComponent("dependency.c")
        let dependencyBinaryURL = directory.appendingPathComponent("libAbsoluteDependency.dylib")
        let mainSourceURL = directory.appendingPathComponent("main.c")
        let mainBinaryURL = directory.appendingPathComponent("libAbsoluteMain.dylib")

        try "int retag_dependency(void) { return 1; }\n".write(to: dependencySourceURL, atomically: true, encoding: .utf8)
        try """
        extern int retag_dependency(void);
        int retag_entrypoint(void) { return retag_dependency(); }
        """.write(to: mainSourceURL, atomically: true, encoding: .utf8)

        try RetagShell.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-macos13.0",
                "-dynamiclib",
                dependencySourceURL.path,
                "-Wl,-install_name,\(dependencyBinaryURL.path)",
                "-o",
                dependencyBinaryURL.path,
            ]
        )

        try RetagShell.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-macos13.0",
                "-dynamiclib",
                mainSourceURL.path,
                "-L\(directory.path)",
                "-lAbsoluteDependency",
                "-Wl,-headerpad,0x4000",
                "-Wl,-install_name,@rpath/libAbsoluteMain.dylib",
                "-o",
                mainBinaryURL.path,
            ]
        )

        return RetagFixture(directory: directory, binaryURL: mainBinaryURL)
    }

    static func makeDyldCacheStyleFixture() throws -> RetagFixture {
        let directory = try makeFixtureDirectory()
        let dependencySourceURL = directory.appendingPathComponent("dependency.c")
        let dependencyBinaryURL = directory.appendingPathComponent("libCacheDependency.dylib")
        let mainSourceURL = directory.appendingPathComponent("main.c")
        let mainBinaryURL = directory.appendingPathComponent("libCacheStyle.dylib")

        try "int cache_dependency(void) { return 2; }\n".write(to: dependencySourceURL, atomically: true, encoding: .utf8)
        try """
        extern int cache_dependency(void);
        int cache_entrypoint(void) { return cache_dependency(); }
        """.write(to: mainSourceURL, atomically: true, encoding: .utf8)

        try RetagShell.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-macos13.0",
                "-dynamiclib",
                dependencySourceURL.path,
                "-Wl,-install_name,/usr/lib/libCacheDependency.dylib",
                "-o",
                dependencyBinaryURL.path,
            ]
        )

        try RetagShell.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-macos13.0",
                "-dynamiclib",
                mainSourceURL.path,
                "-L\(directory.path)",
                "-lCacheDependency",
                "-Wl,-headerpad,0x4000",
                "-Wl,-install_name,/usr/lib/libCacheStyle.dylib",
                "-o",
                mainBinaryURL.path,
            ]
        )

        return RetagFixture(directory: directory, binaryURL: mainBinaryURL)
    }

    static func makeVersionMinStaticArchiveFixture() throws -> RetagFixture {
        let directory = try makeFixtureDirectory()
        let sourceURL = directory.appendingPathComponent("static-fixture.c")
        let objectURL = directory.appendingPathComponent("static-fixture.o")
        let archiveURL = directory.appendingPathComponent("libStaticFixture.a")

        try "int static_fixture_symbol(void) { return 3; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        try RetagShell.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-macos13.0",
                "-c",
                sourceURL.path,
                "-o",
                objectURL.path,
            ]
        )

        try rewriteObjectBuildVersionAsIPhoneOSVersionMin(at: objectURL)

        try RetagShell.run(
            launchPath: "/usr/bin/libtool",
            arguments: [
                "-static",
                "-o",
                archiveURL.path,
                objectURL.path,
            ]
        )

        return RetagFixture(directory: directory, binaryURL: archiveURL)
    }

    static func makeFatVersionMinStaticArchiveFixture() throws -> RetagFixture {
        let directory = try makeFixtureDirectory()
        let sourceURL = directory.appendingPathComponent("fat-static-fixture.c")
        let arm64ObjectURL = directory.appendingPathComponent("fat-static-arm64.o")
        let x86ObjectURL = directory.appendingPathComponent("fat-static-x86_64.o")
        let arm64ArchiveURL = directory.appendingPathComponent("libStaticFixture-arm64.a")
        let x86ArchiveURL = directory.appendingPathComponent("libStaticFixture-x86_64.a")
        let fatArchiveURL = directory.appendingPathComponent("libStaticFixture-fat.a")

        try "int static_fixture_symbol(void) { return 7; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        try RetagShell.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "arm64-apple-ios11.0",
                "-c",
                sourceURL.path,
                "-o",
                arm64ObjectURL.path,
            ]
        )

        try RetagShell.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-ios11.0-simulator",
                "-c",
                sourceURL.path,
                "-o",
                x86ObjectURL.path,
            ]
        )

        try rewriteObjectBuildVersionAsIPhoneOSVersionMin(at: arm64ObjectURL)
        try rewriteObjectBuildVersionAsIPhoneOSVersionMin(at: x86ObjectURL)

        try RetagShell.run(
            launchPath: "/usr/bin/libtool",
            arguments: [
                "-static",
                "-o",
                arm64ArchiveURL.path,
                arm64ObjectURL.path,
            ]
        )

        try RetagShell.run(
            launchPath: "/usr/bin/libtool",
            arguments: [
                "-static",
                "-o",
                x86ArchiveURL.path,
                x86ObjectURL.path,
            ]
        )

        try RetagShell.run(
            launchPath: "/usr/bin/lipo",
            arguments: [
                "-create",
                arm64ArchiveURL.path,
                x86ArchiveURL.path,
                "-output",
                fatArchiveURL.path,
            ]
        )

        return RetagFixture(directory: directory, binaryURL: fatArchiveURL)
    }

    private static func rewriteObjectBuildVersionAsIPhoneOSVersionMin(at objectURL: URL) throws {
        let container = try MachOContainer.parse(at: objectURL)
        let slice = try #require(container.slices.first)
        guard let buildVersion = slice.buildVersion else {
            // Newer toolchains may already emit LC_VERSION_MIN_IPHONEOS for these fixtures.
            return
        }

        var data = try Data(contentsOf: objectURL)
        writeUInt32(UInt32(LC_VERSION_MIN_IPHONEOS), into: &data, at: buildVersion.commandOffset)
        writeUInt32(packedVersion(MachOVersion(major: 11, minor: 0, patch: 0)), into: &data, at: buildVersion.commandOffset + 8)
        writeUInt32(packedVersion(MachOVersion(major: 16, minor: 5, patch: 0)), into: &data, at: buildVersion.commandOffset + 12)
        try data.write(to: objectURL, options: [.atomic])
    }

    private static func packedVersion(_ version: MachOVersion) -> UInt32 {
        UInt32(version.major << 16) | UInt32(version.minor << 8) | UInt32(version.patch)
    }

    private static func writeUInt32(_ value: UInt32, into data: inout Data, at offset: Int) {
        var mutableValue = value
        withUnsafeBytes(of: &mutableValue) { rawBuffer in
            data.replaceSubrange(offset..<(offset + rawBuffer.count), with: rawBuffer)
        }
    }

    private static func makeFixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private enum RetagShell {
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
            let combinedOutput = String(data: outputData + errorData, encoding: .utf8) ?? "unknown error"
            throw RetagShellError.commandFailed(launchPath: launchPath, arguments: arguments, output: combinedOutput)
        }
    }

    static func run(launchPath: String, arguments: [String], currentDirectoryURL: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: launchPath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let combinedOutput = String(data: outputData + errorData, encoding: .utf8) ?? "unknown error"
            throw RetagShellError.commandFailed(launchPath: launchPath, arguments: arguments, output: combinedOutput)
        }
    }

    static func capture(launchPath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let combinedOutput = String(data: outputData + errorData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw RetagShellError.commandFailed(launchPath: launchPath, arguments: arguments, output: combinedOutput)
        }

        return combinedOutput
    }
}

private enum RetagShellError: Error {
    case commandFailed(launchPath: String, arguments: [String], output: String)
}

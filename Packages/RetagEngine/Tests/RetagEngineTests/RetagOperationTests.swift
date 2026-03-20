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
}

private enum RetagShellError: Error {
    case commandFailed(launchPath: String, arguments: [String], output: String)
}

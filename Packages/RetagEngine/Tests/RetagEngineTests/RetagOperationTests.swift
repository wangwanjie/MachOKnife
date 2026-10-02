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

    @Test("platform retag rewrites the selected fat static archive architecture and keeps the others")
    func platformRetagRewritesSelectedFatStaticArchiveArchitecture() throws {
        let fixture = try RetagFixtureFactory.makeFatVersionMinStaticArchiveFixture()
        let outputURL = fixture.directory.appendingPathComponent("rewritten-fat-arm64.a")
        let engine = RetagEngine()

        let result = try engine.retagPlatform(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            platform: .macCatalyst,
            minimumOS: MachOVersion(major: 14, minor: 0, patch: 0),
            sdk: MachOVersion(major: 14, minor: 4, patch: 0),
            architecture: "arm64"
        )

        let inspection = try #require(try ArchiveInspector().inspect(url: outputURL))
        #expect(inspection.kind == .fatArchive)
        #expect(Set(inspection.architectures) == ["arm64", "x86_64"])

        let arm64Slice = try RetagArchiveReader.firstObjectSlice(in: outputURL, architecture: "arm64", scratch: fixture.directory)
        let buildVersion = try #require(arm64Slice.buildVersion)
        #expect(result.diff.entries.contains(where: { $0.kind == .platform }))
        #expect(arm64Slice.versionMin == nil)
        #expect(buildVersion.platform == .macCatalyst)
        #expect(buildVersion.minimumOS == MachOVersion(major: 14, minor: 0, patch: 0))
        #expect(buildVersion.sdk == MachOVersion(major: 14, minor: 4, patch: 0))

        // The unselected architecture must survive untouched.
        let x86Slice = try RetagArchiveReader.firstObjectSlice(in: outputURL, architecture: "x86_64", scratch: fixture.directory)
        let originalX86Slice = try RetagArchiveReader.firstObjectSlice(in: fixture.binaryURL, architecture: "x86_64", scratch: fixture.directory)
        #expect(x86Slice.buildVersion?.platform == originalX86Slice.buildVersion?.platform)
        #expect(x86Slice.versionMin?.platform == originalX86Slice.versionMin?.platform)
        #expect(x86Slice.versionMin?.minimumOS == originalX86Slice.versionMin?.minimumOS)
    }

    @Test("platform retag of a static archive preserves duplicate member names and permissions")
    func platformRetagPreservesDuplicateMembersAndPermissions() throws {
        let fixture = try RetagFixtureFactory.makeDuplicateMemberStaticArchiveFixture()
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: fixture.binaryURL.path)
        let outputURL = fixture.directory.appendingPathComponent("rewritten-duplicates.a")

        try RetagEngine().retagPlatform(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            platform: .macCatalyst,
            minimumOS: MachOVersion(major: 14, minor: 0, patch: 0),
            sdk: MachOVersion(major: 14, minor: 4, patch: 0)
        )

        let inspector = ArchiveInspector()
        let members = try inspector.listMembers(in: outputURL).filter { !ArchiveInspector.isSymbolTableMemberName($0) }
        #expect(members == ["dup.o", "dup.o"])

        let extractionDirectory = fixture.directory.appendingPathComponent("dup-extracted", isDirectory: true)
        let extracted = try inspector.extractIndexedMembers(from: outputURL, to: extractionDirectory)
            .filter { !$0.isSymbolTable }
        #expect(extracted.count == 2)
        for member in extracted {
            let slice = try #require(try MachOContainer.parse(at: member.fileURL).slices.first)
            #expect(slice.buildVersion?.platform == .macCatalyst)
        }

        // Both distinct objects survive (they define different symbols).
        let symbols = try RetagShell.capture(launchPath: "/usr/bin/nm", arguments: ["-g", outputURL.path])
        #expect(symbols.contains("_duplicate_first"))
        #expect(symbols.contains("_duplicate_second"))

        let permissions = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.posixPermissions] as? Int
        #expect(permissions == 0o640)
    }

    @Test("platform retag of a fat Mach-O only rewrites the selected architecture")
    func platformRetagOfFatMachOOnlyRewritesSelectedArchitecture() throws {
        let fixture = try RetagFixtureFactory.makeFatDylibFixture()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.binaryURL.path)
        let outputURL = fixture.directory.appendingPathComponent("retagged-fat.dylib")

        try RetagEngine().retagPlatform(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            platform: .macOS,
            minimumOS: MachOVersion(major: 15, minor: 0, patch: 0),
            sdk: MachOVersion(major: 15, minor: 0, patch: 0),
            architecture: "x86_64"
        )

        let container = try MachOContainer.parse(at: outputURL)
        let x86Slice = try #require(container.slices.first(where: { $0.header.cpuType == CPU_TYPE_X86_64 }))
        let armSlice = try #require(container.slices.first(where: { $0.header.cpuType == CPU_TYPE_ARM64 }))
        #expect(x86Slice.buildVersion?.minimumOS == MachOVersion(major: 15, minor: 0, patch: 0))
        #expect(armSlice.buildVersion?.minimumOS == MachOVersion(major: 13, minor: 0, patch: 0))

        let permissions = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.posixPermissions] as? Int
        #expect(permissions == 0o755)
    }

    @Test("platform retag rejects an architecture missing from a fat Mach-O")
    func platformRetagRejectsMissingArchitecture() throws {
        let fixture = try RetagFixtureFactory.makeFatDylibFixture()
        let outputURL = fixture.directory.appendingPathComponent("never-written.dylib")

        #expect {
            try RetagEngine().retagPlatform(
                inputURL: fixture.binaryURL,
                outputURL: outputURL,
                platform: .macOS,
                minimumOS: MachOVersion(major: 15, minor: 0, patch: 0),
                sdk: MachOVersion(major: 15, minor: 0, patch: 0),
                architecture: "armv7"
            )
        } throws: { error in
            guard case let .architectureNotFound(name, available) = error as? RetagEngineError else { return false }
            return name == "armv7" && Set(available) == ["arm64", "x86_64"]
        }
        #expect(FileManager.default.fileExists(atPath: outputURL.path) == false)
    }

    @Test("platform retag rejects versions that cannot be packed")
    func platformRetagRejectsUnpackableVersions() throws {
        let fixture = try RetagFixtureFactory.makeVersionMinStaticArchiveFixture()
        let outputURL = fixture.directory.appendingPathComponent("never-written.a")

        #expect(throws: MachOVersionPackingError.self) {
            try RetagEngine().retagPlatform(
                inputURL: fixture.binaryURL,
                outputURL: outputURL,
                platform: .macCatalyst,
                minimumOS: MachOVersion(major: 14, minor: 256, patch: 0),
                sdk: MachOVersion(major: 14, minor: 4, patch: 0)
            )
        }
        #expect(throws: MachOVersionPackingError.self) {
            try RetagEngine().previewPlatformRetag(
                inputURL: fixture.binaryURL,
                platform: .macCatalyst,
                minimumOS: MachOVersion(major: 14, minor: 0, patch: 0),
                sdk: MachOVersion(major: 70_000, minor: 0, patch: 0)
            )
        }
        #expect(FileManager.default.fileExists(atPath: outputURL.path) == false)
    }

    @Test("archive member patching supports 32-bit Mach-O objects")
    func archiveMemberPatchingSupports32BitObjects() throws {
        let fixture = try RetagFixtureFactory.makeARMv7ObjectFixture()
        let original = try Data(contentsOf: fixture.binaryURL)

        let patched = try #require(
            try RetagEngine().patchedArchiveObjectData(
                memberName: "armv7.o",
                data: original,
                targetPlatformRawValue: UInt32(PLATFORM_MACCATALYST),
                minimumOS: MachOVersion(major: 14, minor: 0, patch: 0),
                sdk: MachOVersion(major: 14, minor: 4, patch: 0)
            )
        )
        let patchedURL = fixture.directory.appendingPathComponent("armv7-patched.o")
        try patched.write(to: patchedURL)

        let slice = try #require(try MachOContainer.parse(at: patchedURL).slices.first)
        #expect(slice.header.is64Bit == false)
        #expect(slice.versionMin == nil)
        #expect(slice.buildVersion?.platform == .macCatalyst)
        #expect(slice.buildVersion?.minimumOS == MachOVersion(major: 14, minor: 0, patch: 0))

        // Section contents must still be found at the (shifted) section offsets.
        let originalText = try RetagShell.capture(launchPath: "/usr/bin/otool", arguments: ["-t", fixture.binaryURL.path])
            .split(separator: "\n").dropFirst().joined(separator: "\n")
        let patchedText = try RetagShell.capture(launchPath: "/usr/bin/otool", arguments: ["-t", patchedURL.path])
            .split(separator: "\n").dropFirst().joined(separator: "\n")
        #expect(originalText == patchedText)
        #expect(originalText.isEmpty == false)
    }

    @Test("archive member patching rejects byte-swapped Mach-O objects")
    func archiveMemberPatchingRejectsByteSwappedObjects() throws {
        var data = Data(count: 32)
        data.replaceSubrange(0..<4, with: withUnsafeBytes(of: MH_CIGAM_64) { Data($0) })

        #expect(throws: RetagEngineError.byteSwappedArchiveMember("swapped.o")) {
            try RetagEngine().patchedArchiveObjectData(
                memberName: "swapped.o",
                data: data,
                targetPlatformRawValue: UInt32(PLATFORM_MACCATALYST),
                minimumOS: MachOVersion(major: 14, minor: 0, patch: 0),
                sdk: MachOVersion(major: 14, minor: 4, patch: 0)
            )
        }
    }
}

private enum RetagArchiveReader {
    /// Thins `archiveURL` (when fat) and returns the first object member's slice for `architecture`.
    static func firstObjectSlice(in archiveURL: URL, architecture: String, scratch: URL) throws -> MachOSlice {
        let directory = scratch.appendingPathComponent("read-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let extraction = try ArchiveInspector().extractThinArchive(url: archiveURL, preferredArchitecture: architecture)
        defer { try? FileManager.default.removeItem(at: extraction.archiveURL.deletingLastPathComponent()) }
        let members = try ArchiveInspector().extractIndexedMembers(from: extraction.archiveURL, to: directory)
        let member = try #require(members.first(where: { !$0.isSymbolTable }))
        return try #require(try MachOContainer.parse(at: member.fileURL).slices.first)
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

    static func makeDuplicateMemberStaticArchiveFixture() throws -> RetagFixture {
        let directory = try makeFixtureDirectory()
        let archiveURL = directory.appendingPathComponent("libDuplicates.a")
        var objectPaths: [String] = []

        for name in ["first", "second"] {
            let subdirectory = directory.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
            let sourceURL = subdirectory.appendingPathComponent("dup.c")
            let objectURL = subdirectory.appendingPathComponent("dup.o")
            try "int duplicate_\(name)(void) { return 1; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)
            try RetagShell.run(
                launchPath: "/usr/bin/clang",
                arguments: ["-target", "x86_64-apple-macos13.0", "-c", sourceURL.path, "-o", objectURL.path]
            )
            objectPaths.append(objectURL.path)
        }

        try RetagShell.run(launchPath: "/usr/bin/ar", arguments: ["-q", archiveURL.path] + objectPaths)
        return RetagFixture(directory: directory, binaryURL: archiveURL)
    }

    static func makeFatDylibFixture() throws -> RetagFixture {
        let directory = try makeFixtureDirectory()
        let sourceURL = directory.appendingPathComponent("fat.c")
        let binaryURL = directory.appendingPathComponent("libFat.dylib")
        try "int fat_symbol(void) { return 9; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try RetagShell.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-arch", "arm64", "-arch", "x86_64",
                "-mmacosx-version-min=13.0",
                "-dynamiclib", sourceURL.path,
                "-Wl,-headerpad,0x1000",
                "-o", binaryURL.path,
            ]
        )
        return RetagFixture(directory: directory, binaryURL: binaryURL)
    }

    static func makeARMv7ObjectFixture() throws -> RetagFixture {
        let directory = try makeFixtureDirectory()
        let sourceURL = directory.appendingPathComponent("armv7.c")
        let objectURL = directory.appendingPathComponent("armv7.o")
        try "int armv7_symbol(int x) { return x * 3 + 1; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try RetagShell.run(
            launchPath: "/usr/bin/clang",
            arguments: ["-target", "armv7-apple-ios9.0", "-Wno-incompatible-sysroot", "-c", sourceURL.path, "-o", objectURL.path]
        )
        return RetagFixture(directory: directory, binaryURL: objectURL)
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

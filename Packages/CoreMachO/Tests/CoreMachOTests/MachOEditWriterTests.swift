import Foundation
import MachO
import Testing
@testable import CoreMachO

struct MachOEditWriterTests {
    @Test("rewrites install name and dylib dependency paths")
    func rewritesInstallNameAndDylibDependencyPaths() throws {
        let fixture = try WriterFixtureFactory.makeSignedDynamicLibraryFixture()
        let outputURL = fixture.directory.appendingPathComponent("rewritten-id.dylib")

        let result = try MachOWriter().write(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(
                installName: "@rpath/libWriterFixturePatched.dylib",
                dylibEdits: [
                    .replace(
                        oldPath: fixture.dependencyInstallName,
                        newPath: "@rpath/libAbsoluteDependency.dylib"
                    ),
                ]
            )
        )

        let container = try MachOContainer.parse(at: outputURL)
        let slice = try #require(container.slices.first)

        #expect(slice.installName == "@rpath/libWriterFixturePatched.dylib")
        #expect(slice.dylibReferences.contains(where: { $0.path == "@rpath/libAbsoluteDependency.dylib" }))
        #expect(result.diff.entries.contains(where: { $0.kind == .installName }))
        #expect(result.diff.entries.contains(where: { $0.kind == .dylib }))
    }

    @Test("adds and removes rpaths in the load-command area")
    func addsAndRemovesRPathsInTheLoadCommandArea() throws {
        let fixture = try WriterFixtureFactory.makeSignedDynamicLibraryFixture()
        let outputURL = fixture.directory.appendingPathComponent("rewritten-rpath.dylib")

        _ = try MachOWriter().write(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(
                rpathEdits: [
                    .remove("@loader_path/Frameworks"),
                    .add("@executable_path/Frameworks"),
                ]
            )
        )

        let container = try MachOContainer.parse(at: outputURL)
        let slice = try #require(container.slices.first)

        #expect(slice.rpaths.contains("@executable_path/Frameworks"))
        #expect(slice.rpaths.contains("@loader_path/Frameworks") == false)
    }

    @Test("rewrites build version and segment protections")
    func rewritesBuildVersionAndSegmentProtections() throws {
        let fixture = try WriterFixtureFactory.makeSignedDynamicLibraryFixture()
        let outputURL = fixture.directory.appendingPathComponent("rewritten-platform.dylib")

        _ = try MachOWriter().write(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(
                platformEdit: PlatformEdit(
                    platform: .macOS,
                    minimumOS: MachOVersion(major: 14, minor: 0, patch: 0),
                    sdk: MachOVersion(major: 14, minor: 4, patch: 0)
                ),
                segmentProtectionEdits: [
                    SegmentProtectionEdit(
                        segmentName: "__DATA_CONST",
                        maxProtection: [.read, .write],
                        initialProtection: [.read]
                    ),
                ]
            )
        )

        let container = try MachOContainer.parse(at: outputURL)
        let slice = try #require(container.slices.first)
        let buildVersion = try #require(slice.buildVersion)
        let dataSegment = try #require(slice.segments.first(where: { $0.name == "__DATA_CONST" }))

        #expect(buildVersion.platform == .macOS)
        #expect(buildVersion.minimumOS == MachOVersion(major: 14, minor: 0, patch: 0))
        #expect(buildVersion.sdk == MachOVersion(major: 14, minor: 4, patch: 0))
        #expect(dataSegment.maxProtection == [.read, .write])
        #expect(dataSegment.initialProtection == [.read])
    }

    @Test("removes LC_CODE_SIGNATURE when stripping signatures")
    func removesCodeSignatureWhenStrippingSignatures() throws {
        let fixture = try WriterFixtureFactory.makeSignedDynamicLibraryFixture()
        let outputURL = fixture.directory.appendingPathComponent("rewritten-unsigned.dylib")

        let result = try MachOWriter().write(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(stripCodeSignature: true)
        )

        let container = try MachOContainer.parse(at: outputURL)
        let slice = try #require(container.slices.first)

        #expect(result.removedCodeSignature)
        #expect(slice.codeSignature == nil)
    }

    @Test("converts version-min commands to build-version when retagging to mac catalyst")
    func convertsVersionMinCommandsToBuildVersionForMacCatalyst() throws {
        let fixture = try WriterFixtureFactory.makeVersionMinDynamicLibraryFixture()
        let outputURL = fixture.directory.appendingPathComponent("rewritten-catalyst.dylib")

        _ = try MachOWriter().write(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(
                platformEdit: PlatformEdit(
                    platform: .macCatalyst,
                    minimumOS: MachOVersion(major: 14, minor: 0, patch: 0),
                    sdk: MachOVersion(major: 14, minor: 4, patch: 0)
                )
            )
        )

        let container = try MachOContainer.parse(at: outputURL)
        let slice = try #require(container.slices.first)
        let buildVersion = try #require(slice.buildVersion)

        #expect(slice.versionMin == nil)
        #expect(buildVersion.platform == .macCatalyst)
        #expect(buildVersion.minimumOS == MachOVersion(major: 14, minor: 0, patch: 0))
        #expect(buildVersion.sdk == MachOVersion(major: 14, minor: 4, patch: 0))
    }
}

private struct WriterFixture {
    let directory: URL
    let binaryURL: URL
    let dependencyInstallName: String
}

private enum WriterFixtureFactory {
    static func makeSignedDynamicLibraryFixture() throws -> WriterFixture {
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        let dependencySourceURL = sourceDirectory.appendingPathComponent("dependency.c")
        let dependencyBinaryURL = sourceDirectory.appendingPathComponent("libAbsoluteDependency.dylib")
        let dependencyInstallName = dependencyBinaryURL.path

        let mainSourceURL = sourceDirectory.appendingPathComponent("fixture.c")
        let mainBinaryURL = sourceDirectory.appendingPathComponent("libWriterFixture.dylib")

        try """
        int writer_dependency_value(void) { return 9; }
        """.write(to: dependencySourceURL, atomically: true, encoding: .utf8)

        try """
        extern int writer_dependency_value(void);
        int writer_fixture_entrypoint(void) { return writer_dependency_value(); }
        """.write(to: mainSourceURL, atomically: true, encoding: .utf8)

        try FixtureCommand.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-macos13.0",
                "-dynamiclib",
                dependencySourceURL.path,
                "-Wl,-install_name,\(dependencyInstallName)",
                "-o",
                dependencyBinaryURL.path,
            ]
        )

        try FixtureCommand.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-macos13.0",
                "-dynamiclib",
                mainSourceURL.path,
                "-L\(sourceDirectory.path)",
                "-lAbsoluteDependency",
                "-Wl,-headerpad,0x4000",
                "-Wl,-install_name,@rpath/libWriterFixture.dylib",
                "-Wl,-rpath,@loader_path/Frameworks",
                "-o",
                mainBinaryURL.path,
            ]
        )

        try FixtureCommand.run(
            launchPath: "/usr/bin/codesign",
            arguments: [
                "-s", "-",
                mainBinaryURL.path,
            ]
        )

        return WriterFixture(
            directory: sourceDirectory,
            binaryURL: mainBinaryURL,
            dependencyInstallName: dependencyInstallName
        )
    }

    static func makeVersionMinDynamicLibraryFixture() throws -> WriterFixture {
        let fixture = try makeSignedDynamicLibraryFixture()
        let container = try MachOContainer.parse(at: fixture.binaryURL)
        let slice = try #require(container.slices.first)
        let buildVersion = try #require(slice.buildVersion)

        var data = try Data(contentsOf: fixture.binaryURL)
        writeUInt32(UInt32(LC_VERSION_MIN_IPHONEOS), into: &data, at: buildVersion.commandOffset)
        writeUInt32(packedVersion(MachOVersion(major: 11, minor: 0, patch: 0)), into: &data, at: buildVersion.commandOffset + 8)
        writeUInt32(packedVersion(MachOVersion(major: 16, minor: 5, patch: 0)), into: &data, at: buildVersion.commandOffset + 12)
        try data.write(to: fixture.binaryURL, options: [.atomic])

        return fixture
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
}

private enum FixtureCommand {
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
            throw FixtureCommandError.commandFailed(launchPath: launchPath, arguments: arguments, output: combinedOutput)
        }
    }
}

private enum FixtureCommandError: Error {
    case commandFailed(launchPath: String, arguments: [String], output: String)
}

struct MachOWriterHardeningTests {
    @Test("added dylib commands use timestamp 2 and the requested versions instead of copying another dylib")
    func addedDylibUsesConventionalMetadata() throws {
        let fixture = try WriterFixtureFactory.makeSignedDynamicLibraryFixture()
        let outputURL = fixture.directory.appendingPathComponent("added-dylib.dylib")

        _ = try MachOWriter().write(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(
                dylibEdits: [
                    .add(path: "@rpath/libDefaultVersions.dylib", command: UInt32(LC_LOAD_DYLIB)),
                    .add(
                        path: "@rpath/libExplicitVersions.dylib",
                        command: UInt32(LC_LOAD_WEAK_DYLIB),
                        currentVersion: MachOVersion(major: 3, minor: 2, patch: 1),
                        compatibilityVersion: MachOVersion(major: 1, minor: 0, patch: 0)
                    ),
                ]
            )
        )

        let slice = try #require(try MachOContainer.parse(at: outputURL).slices.first)
        let defaulted = try #require(slice.dylibReferences.first(where: { $0.path == "@rpath/libDefaultVersions.dylib" }))
        let explicit = try #require(slice.dylibReferences.first(where: { $0.path == "@rpath/libExplicitVersions.dylib" }))

        #expect(defaulted.timestamp == 2)
        #expect(defaulted.currentVersion == MachOVersion(major: 0, minor: 0, patch: 0))
        #expect(defaulted.compatibilityVersion == MachOVersion(major: 0, minor: 0, patch: 0))
        #expect(explicit.timestamp == 2)
        #expect(explicit.command == UInt32(LC_LOAD_WEAK_DYLIB))
        #expect(explicit.currentVersion == MachOVersion(major: 3, minor: 2, patch: 1))
        #expect(explicit.compatibilityVersion == MachOVersion(major: 1, minor: 0, patch: 0))
    }

    @Test("rejects versions that do not fit the packed encoding")
    func rejectsOutOfRangeVersions() throws {
        let fixture = try WriterFixtureFactory.makeSignedDynamicLibraryFixture()
        let outputURL = fixture.directory.appendingPathComponent("invalid-version.dylib")

        #expect(throws: MachOWriteError.self) {
            try MachOWriter().write(
                inputURL: fixture.binaryURL,
                outputURL: outputURL,
                editPlan: MachOEditPlan(
                    platformEdit: PlatformEdit(
                        platform: .macOS,
                        minimumOS: MachOVersion(major: 14, minor: 256, patch: 0),
                        sdk: MachOVersion(major: 14, minor: 0, patch: 0)
                    )
                )
            )
        }
        #expect(FileManager.default.fileExists(atPath: outputURL.path) == false)
    }

    @Test("preserves the input file permissions on the output")
    func preservesPermissions() throws {
        let fixture = try WriterFixtureFactory.makeSignedDynamicLibraryFixture()
        try FileManager.default.setAttributes([.posixPermissions: 0o750], ofItemAtPath: fixture.binaryURL.path)
        let outputURL = fixture.directory.appendingPathComponent("permissions.dylib")

        _ = try MachOWriter().write(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(rpathEdits: [.add("@executable_path/Libs")])
        )

        let permissions = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.posixPermissions] as? Int
        #expect(permissions == 0o750)
    }

    @Test("install name edits fail clearly when the slice has no LC_ID_DYLIB")
    func installNameEditRequiresIDCommand() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("tool.c")
        let binaryURL = directory.appendingPathComponent("tool")
        try "int main(void) { return 0; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try FixtureCommand.run(
            launchPath: "/usr/bin/clang",
            arguments: ["-target", "x86_64-apple-macos13.0", sourceURL.path, "-o", binaryURL.path]
        )

        #expect {
            try MachOWriter().write(
                inputURL: binaryURL,
                outputURL: directory.appendingPathComponent("tool-out"),
                editPlan: MachOEditPlan(installName: "@rpath/tool")
            )
        } throws: { error in
            guard case .missingInstallNameCommand = error as? MachOWriteError else { return false }
            return true
        }
    }

    @Test("refuses to edit byte-swapped (big-endian) slices")
    func refusesByteSwappedSlices() throws {
        var data = Data()
        func appendBigEndian(_ value: UInt32) {
            withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
        }
        appendBigEndian(MH_MAGIC_64)
        appendBigEndian(UInt32(bitPattern: CPU_TYPE_POWERPC64))
        appendBigEndian(0)
        appendBigEndian(UInt32(MH_DYLIB))
        appendBigEndian(0)
        appendBigEndian(0)
        appendBigEndian(0)
        appendBigEndian(0)
        data.append(Data(count: 64))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let inputURL = directory.appendingPathComponent("big-endian")
        try data.write(to: inputURL)

        #expect {
            try MachOWriter().write(
                inputURL: inputURL,
                outputURL: directory.appendingPathComponent("out"),
                editPlan: MachOEditPlan(rpathEdits: [.add("@loader_path")])
            )
        } throws: { error in
            guard case .byteSwappedSliceUnsupported = error as? MachOWriteError else { return false }
            return true
        }
    }

    @Test("rejects load command areas that overlap file content")
    func rejectsMalformedLoadCommandArea() throws {
        // One LC_SEGMENT_64 whose file offset (40) lies inside its own load command.
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        append(MH_MAGIC_64)
        append(UInt32(bitPattern: CPU_TYPE_X86_64))
        append(UInt32(3))
        append(UInt32(MH_DYLIB))
        append(UInt32(1))
        append(UInt32(72))
        append(UInt32(0))
        append(UInt32(0))
        append(UInt32(LC_SEGMENT_64))
        append(UInt32(72))
        data.append(Data("__DATA".utf8) + Data(count: 10))
        append(UInt64(0x1000))
        append(UInt64(0x1000))
        append(UInt64(40))
        append(UInt64(16))
        append(Int32(3))
        append(Int32(3))
        append(UInt32(0))
        append(UInt32(0))
        data.append(Data(count: 256))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let inputURL = directory.appendingPathComponent("overlap")
        try data.write(to: inputURL)

        #expect {
            try MachOWriter().write(
                inputURL: inputURL,
                outputURL: directory.appendingPathComponent("out"),
                editPlan: MachOEditPlan(rpathEdits: [.add("@loader_path")])
            )
        } throws: { error in
            guard case .malformedLoadCommandArea = error as? MachOWriteError else { return false }
            return true
        }
    }
}

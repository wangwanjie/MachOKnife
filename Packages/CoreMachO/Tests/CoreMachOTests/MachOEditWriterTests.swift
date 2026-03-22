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

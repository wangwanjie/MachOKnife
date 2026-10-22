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
        #expect(slice.dylibReferences.contains(where: { $0.path == fixture.dependencyInstallName }) == false)
        #expect(slice.codeSignature == nil)
        #expect(result.removedCodeSignature)
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

struct MachOWriterSignatureAndPlatformTests {
    @Test("edits that change nothing keep the code signature and the file bytes")
    func noOpEditKeepsCodeSignature() throws {
        let fixture = try WriterFixtureFactory.makeSignedDynamicLibraryFixture()
        let outputURL = fixture.directory.appendingPathComponent("noop.dylib")

        let result = try MachOWriter().write(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(rpathEdits: [.remove("@executable_path/DoesNotExist")])
        )

        #expect(result.diff.entries.isEmpty)
        #expect(result.removedCodeSignature == false)
        #expect(try Data(contentsOf: outputURL) == Data(contentsOf: fixture.binaryURL))
        try FixtureCommand.run(launchPath: "/usr/bin/codesign", arguments: ["-v", outputURL.path])
    }

    @Test("real edits drop the now-invalid signature")
    func realEditDropsSignature() throws {
        let fixture = try WriterFixtureFactory.makeSignedDynamicLibraryFixture()
        let outputURL = fixture.directory.appendingPathComponent("edited.dylib")

        let result = try MachOWriter().write(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(rpathEdits: [.add("@executable_path/Frameworks")])
        )

        let slice = try #require(try MachOContainer.parse(at: outputURL).slices.first)
        #expect(result.removedCodeSignature)
        #expect(slice.codeSignature == nil)
        #expect(result.diff.entries.contains(where: { $0.kind == .codeSignature }))
    }

    @Test("stripping a thin signature truncates it like codesign --remove-signature")
    func stripTruncatesThinSignature() throws {
        let fixture = try WriterFixtureFactory.makeSignedDynamicLibraryFixture()
        let original = try #require(try MachOContainer.parse(at: fixture.binaryURL).slices.first)
        let signature = try #require(original.codeSignature)
        let originalLinkEdit = try #require(original.segments.first(where: { $0.name == "__LINKEDIT" }))
        let outputURL = fixture.directory.appendingPathComponent("stripped.dylib")

        _ = try MachOWriter().write(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(stripCodeSignature: true)
        )

        let stripped = try #require(try MachOContainer.parse(at: outputURL).slices.first)
        let linkEdit = try #require(stripped.segments.first(where: { $0.name == "__LINKEDIT" }))
        let outputSize = try Data(contentsOf: outputURL).count
        #expect(outputSize == Int(signature.dataOffset))
        #expect(linkEdit.fileOffset + linkEdit.fileSize == UInt64(signature.dataOffset))
        #expect(linkEdit.vmSize == originalLinkEdit.vmSize)

        // codesign 还会去掉签名前用于 16 字节对齐的少量填充，因此结果只会比我们小不超过 16 字节；
        // 输出必须可以重新签名并通过严格校验。
        let reference = fixture.directory.appendingPathComponent("reference.dylib")
        try FileManager.default.copyItem(at: fixture.binaryURL, to: reference)
        try FixtureCommand.run(launchPath: "/usr/bin/codesign", arguments: ["--remove-signature", reference.path])
        let referenceSize = try Data(contentsOf: reference).count
        #expect(referenceSize <= outputSize)
        #expect(outputSize - referenceSize < 16)
        try FixtureCommand.run(launchPath: "/usr/bin/codesign", arguments: ["-s", "-", outputURL.path])
        try FixtureCommand.run(launchPath: "/usr/bin/codesign", arguments: ["-v", "--strict", outputURL.path])
    }

    @Test("stripping fat signatures updates fat_arch sizes and keeps slices re-signable")
    func stripUpdatesFatSliceSizes() throws {
        let fixture = try WriterFixtureFactory.makeSignedFatDynamicLibraryFixture()
        let outputURL = fixture.directory.appendingPathComponent("stripped-fat.dylib")

        let result = try MachOWriter().write(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(stripCodeSignature: true)
        )

        let data = try Data(contentsOf: outputURL)
        let container = try MachOContainer.parse(at: outputURL)
        let entries = try MachOFileParser(data: data).fatArchitectureEntries()
        #expect(result.removedCodeSignature)
        #expect(container.slices.count == 2)
        for slice in container.slices {
            let entry = try #require(entries.first(where: { $0.offset == slice.offset }))
            let linkEdit = try #require(slice.segments.first(where: { $0.name == "__LINKEDIT" }))
            #expect(slice.codeSignature == nil)
            #expect(entry.size == linkEdit.fileOffset + linkEdit.fileSize)
        }
        // 文件末尾即最后一个切片的末尾，旧签名不再残留。
        let lastEntry = try #require(entries.max(by: { $0.offset < $1.offset }))
        #expect(data.count == lastEntry.offset + Int(lastEntry.size))

        try FixtureCommand.run(launchPath: "/usr/bin/codesign", arguments: ["-s", "-", outputURL.path])
        try FixtureCommand.run(launchPath: "/usr/bin/codesign", arguments: ["-v", "--strict", "--all-architectures", outputURL.path])
    }

    @Test("duplicate segment protection edits do not crash and the last one wins")
    func duplicateSegmentProtectionEditsUseLastValue() throws {
        let fixture = try WriterFixtureFactory.makeSignedDynamicLibraryFixture()
        let outputURL = fixture.directory.appendingPathComponent("duplicate-segment-edits.dylib")

        _ = try MachOWriter().write(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(
                segmentProtectionEdits: [
                    SegmentProtectionEdit(segmentName: "__DATA_CONST", initialProtection: [.read, .write]),
                    SegmentProtectionEdit(segmentName: "__DATA_CONST", initialProtection: [.read]),
                ]
            )
        )

        let slice = try #require(try MachOContainer.parse(at: outputURL).slices.first)
        let segment = try #require(slice.segments.first(where: { $0.name == "__DATA_CONST" }))
        #expect(segment.initialProtection == [.read])
    }

    @Test("platform edits never leave duplicate version commands behind")
    func platformEditCollapsesVersionCommands() throws {
        let fixture = try WriterFixtureFactory.makeSignedDynamicLibraryFixture()
        let slice = try #require(try MachOContainer.parse(at: fixture.binaryURL).slices.first)
        let buildVersion = try #require(slice.buildVersion)
        let data = try Data(contentsOf: fixture.binaryURL)

        // 追加一条 LC_VERSION_MIN_MACOSX 和一条重复的 LC_BUILD_VERSION（模拟 zippered 二进制）。
        var versionMin = Data()
        versionMin.appendLittleEndian(UInt32(LC_VERSION_MIN_MACOSX))
        versionMin.appendLittleEndian(UInt32(16))
        versionMin.appendLittleEndian(UInt32(0x000D_0000))
        versionMin.appendLittleEndian(UInt32(0x000D_0000))
        let duplicateBuildVersion = data.subdata(in: buildVersion.commandOffset..<(buildVersion.commandOffset + 32))
        try WriterFixtureFactory.appendLoadCommands([versionMin, duplicateBuildVersion], to: fixture.binaryURL)

        let prepared = try #require(try MachOContainer.parse(at: fixture.binaryURL).slices.first)
        #expect(prepared.loadCommands.filter { $0.command == UInt32(LC_BUILD_VERSION) }.count == 2)
        #expect(prepared.versionMin != nil)

        let outputURL = fixture.directory.appendingPathComponent("collapsed.dylib")
        _ = try MachOWriter().write(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(
                platformEdit: PlatformEdit(
                    platform: .macCatalyst,
                    minimumOS: MachOVersion(major: 15, minor: 0, patch: 0),
                    sdk: MachOVersion(major: 15, minor: 0, patch: 0)
                )
            )
        )

        let rewritten = try #require(try MachOContainer.parse(at: outputURL).slices.first)
        let versionCommands = rewritten.loadCommands.filter {
            [UInt32(LC_BUILD_VERSION), UInt32(LC_VERSION_MIN_MACOSX), UInt32(LC_VERSION_MIN_IPHONEOS)].contains($0.command)
        }
        #expect(versionCommands.count == 1)
        #expect(rewritten.buildVersion?.platform == .macCatalyst)
        #expect(rewritten.buildVersion?.minimumOS == MachOVersion(major: 15, minor: 0, patch: 0))
    }
}

extension WriterFixtureFactory {
    static func makeSignedFatDynamicLibraryFixture() throws -> WriterFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("fat.c")
        let binaryURL = directory.appendingPathComponent("libFatSigned.dylib")
        try "int fat_signed_value(void) { return 5; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        try FixtureCommand.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-arch", "arm64", "-arch", "x86_64",
                "-mmacosx-version-min=13.0",
                "-dynamiclib", sourceURL.path,
                "-o", binaryURL.path,
            ]
        )
        try FixtureCommand.run(launchPath: "/usr/bin/codesign", arguments: ["-f", "-s", "-", binaryURL.path])
        return WriterFixture(directory: directory, binaryURL: binaryURL, dependencyInstallName: "")
    }

    /// 把若干加载命令追加到 thin 文件的加载命令区（使用 headerpad 预留的空间）。
    static func appendLoadCommands(_ commands: [Data], to url: URL) throws {
        var data = try Data(contentsOf: url)
        let commandCount = data.readLittleEndian(UInt32.self, at: 16)
        let sizeofCommands = data.readLittleEndian(UInt32.self, at: 20)
        var cursor = 32 + Int(sizeofCommands)
        for command in commands {
            data.replaceSubrange(cursor..<(cursor + command.count), with: command)
            cursor += command.count
        }
        let added = commands.reduce(0) { $0 + $1.count }
        data.writeLittleEndian(commandCount + UInt32(commands.count), at: 16)
        data.writeLittleEndian(sizeofCommands + UInt32(added), at: 20)
        try data.write(to: url, options: [.atomic])
    }
}

import CoreMachO
import Foundation
import MachO

public struct RetagEngine: Sendable {
    private let writer = MachOWriter()
    private let archiveInspector = ArchiveInspector()

    public init() {}

    public func previewPlatformRetag(
        inputURL: URL,
        platform: MachOPlatform,
        minimumOS: MachOVersion,
        sdk: MachOVersion,
        architecture: String? = nil
    ) throws -> RetagPreview {
        let plan = MachOEditPlan(
            platformEdit: PlatformEdit(platform: platform, minimumOS: minimumOS, sdk: sdk)
        )
        if try archiveInspector.inspect(url: inputURL) != nil {
            let temporaryOutputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("MachOKnifeRetagPreview-\(UUID().uuidString).a")
            let result = try retagArchive(
                inputURL: inputURL,
                outputURL: temporaryOutputURL,
                plan: plan,
                architecture: architecture
            )
            return RetagPreview(diff: result.diff)
        }
        return try RetagPreview(diff: writer.preview(inputURL: inputURL, editPlan: plan))
    }

    public func retagPlatform(
        inputURL: URL,
        outputURL: URL,
        platform: MachOPlatform,
        minimumOS: MachOVersion,
        sdk: MachOVersion,
        architecture: String? = nil
    ) throws -> RetagResult {
        let plan = MachOEditPlan(
            platformEdit: PlatformEdit(platform: platform, minimumOS: minimumOS, sdk: sdk)
        )
        if try archiveInspector.inspect(url: inputURL) != nil {
            return try retagArchive(
                inputURL: inputURL,
                outputURL: outputURL,
                plan: plan,
                architecture: architecture
            )
        }
        let result = try writer.write(inputURL: inputURL, outputURL: outputURL, editPlan: plan)
        return RetagResult(outputURL: result.outputURL, diff: result.diff)
    }

    public func rewriteDylibPaths(
        inputURL: URL,
        outputURL: URL,
        fromPrefix: String,
        toPrefix: String
    ) throws -> RetagResult {
        let container = try MachOContainer.parse(at: inputURL)
        let dylibEdits: [DylibEdit] = container.slices.flatMap { slice in
            slice.dylibReferences.compactMap { reference in
                guard reference.path.hasPrefix(fromPrefix) else { return nil }
                let suffix = String(reference.path.dropFirst(fromPrefix.count))
                return DylibEdit.replace(oldPath: reference.path, newPath: toPrefix + suffix, command: reference.command)
            }
        }

        let writeResult = try writer.write(
            inputURL: inputURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(dylibEdits: dylibEdits)
        )

        return RetagResult(outputURL: writeResult.outputURL, diff: writeResult.diff)
    }

    public func previewFixDyldCacheDylib(inputURL: URL) throws -> RetagPreview {
        let plan = try makeDyldCacheFixPlan(inputURL: inputURL)
        return try RetagPreview(diff: writer.preview(inputURL: inputURL, editPlan: plan))
    }

    public func fixDyldCacheDylib(inputURL: URL, outputURL: URL) throws -> RetagResult {
        let plan = try makeDyldCacheFixPlan(inputURL: inputURL)
        let result = try writer.write(inputURL: inputURL, outputURL: outputURL, editPlan: plan)
        return RetagResult(outputURL: result.outputURL, diff: result.diff)
    }

    private func makeDyldCacheFixPlan(inputURL: URL) throws -> MachOEditPlan {
        let container = try MachOContainer.parse(at: inputURL)
        guard let slice = container.slices.first else {
            return MachOEditPlan()
        }

        let installName = slice.installName ?? inputURL.path
        let absoluteDirectory = URL(filePath: installName).deletingLastPathComponent().path + "/"
        let rewrittenInstallName = "@rpath/" + URL(filePath: installName).lastPathComponent

        var dylibEdits = [DylibEdit]()
        for reference in slice.dylibReferences where reference.path.hasPrefix(absoluteDirectory) {
            dylibEdits.append(
                .replace(
                    oldPath: reference.path,
                    newPath: "@rpath/" + URL(filePath: reference.path).lastPathComponent,
                    command: reference.command
                )
            )
        }

        var rpathEdits = [RPathEdit]()
        if slice.rpaths.contains("@loader_path") == false {
            rpathEdits.append(.add("@loader_path"))
        }

        return MachOEditPlan(
            installName: rewrittenInstallName,
            dylibEdits: dylibEdits,
            rpathEdits: rpathEdits
        )
    }

    private func retagArchive(
        inputURL: URL,
        outputURL: URL,
        plan: MachOEditPlan,
        architecture: String?
    ) throws -> RetagResult {
        guard let platformEdit = plan.platformEdit else {
            throw ArchiveInspectorError.unsupportedArchive(inputURL)
        }

        let extraction = try archiveInspector.extractThinArchive(
            url: inputURL,
            preferredArchitecture: architecture
        )
        let members = try archiveInspector.listMembers(in: extraction.archiveURL)
            .filter { !$0.hasPrefix("__.SYMDEF") }

        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MachOKnifeArchiveRetag-\(UUID().uuidString)", isDirectory: true)
        let extractedDirectory = workingDirectory.appendingPathComponent("members", isDirectory: true)
        let patchedDirectory = workingDirectory.appendingPathComponent("patched", isDirectory: true)
        try FileManager.default.createDirectory(at: extractedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: patchedDirectory, withIntermediateDirectories: true)
        try archiveInspector.extractMembers(from: extraction.archiveURL, to: extractedDirectory)

        var diffEntries = [DiffEntry]()
        for member in members {
            let sourceMemberURL = extractedDirectory.appendingPathComponent(member)
            let patchedMemberURL = patchedDirectory.appendingPathComponent(member)
            let wasPatched = try patchArchiveMemberIfNeeded(
                sourceURL: sourceMemberURL,
                destinationURL: patchedMemberURL,
                platformEdit: platformEdit
            )
            if wasPatched {
                diffEntries.append(
                    DiffEntry(
                        sliceOffset: 0,
                        kind: .platform,
                        originalValue: member,
                        updatedValue: "\(member) -> \(platformEdit.platform) \(platformEdit.minimumOS) \(platformEdit.sdk)"
                    )
                )
            }
        }

        try rebuildArchive(
            outputURL: outputURL,
            members: members,
            patchedDirectory: patchedDirectory
        )
        return RetagResult(outputURL: outputURL, diff: MachODiff(entries: diffEntries))
    }

    private func patchArchiveMemberIfNeeded(
        sourceURL: URL,
        destinationURL: URL,
        platformEdit: PlatformEdit
    ) throws -> Bool {
        let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        guard let patchedData = try patchedArchiveObjectData(
            data: data,
            targetPlatformRawValue: rawValue(for: platformEdit.platform),
            minimumOS: platformEdit.minimumOS,
            sdk: platformEdit.sdk
        ) else {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return false
        }

        try patchedData.write(to: destinationURL, options: [.atomic])
        return true
    }

    private func patchedArchiveObjectData(
        data: Data,
        targetPlatformRawValue: UInt32,
        minimumOS: MachOVersion,
        sdk: MachOVersion
    ) throws -> Data? {
        guard data.count >= 32 else { return nil }
        let magic = data.readUInt32(at: 0)
        let fileType = data.readUInt32(at: 12)
        guard magic == MH_MAGIC_64, fileType == UInt32(MH_OBJECT) else {
            return nil
        }

        let commandCount = Int(data.readUInt32(at: 16))
        let sizeofCommands = Int(data.readUInt32(at: 20))
        var commandOffset = 32
        var versionCommandOffset: Int?
        var versionCommandSize = 0
        var versionCommandKind: UInt32 = 0

        for _ in 0..<commandCount {
            guard commandOffset + 8 <= data.count else { break }
            let command = data.readUInt32(at: commandOffset)
            let commandSize = Int(data.readUInt32(at: commandOffset + 4))
            guard commandSize > 0, commandOffset + commandSize <= data.count else { break }

            if supportedVersionCommands.contains(command) || command == UInt32(LC_BUILD_VERSION) {
                versionCommandOffset = commandOffset
                versionCommandSize = commandSize
                versionCommandKind = command
                break
            }
            commandOffset += commandSize
        }

        guard let versionCommandOffset else {
            return nil
        }

        let encodedMinimumOS = packedVersion(minimumOS)
        let encodedSDK = packedVersion(sdk)

        if versionCommandKind == UInt32(LC_BUILD_VERSION) {
            var patched = data
            patched.writeUInt32(targetPlatformRawValue, at: versionCommandOffset + 8)
            patched.writeUInt32(encodedMinimumOS, at: versionCommandOffset + 12)
            patched.writeUInt32(encodedSDK, at: versionCommandOffset + 16)
            return patched
        }

        let buildVersionCommand = buildVersionCommandData(
            platformRawValue: targetPlatformRawValue,
            minimumOS: encodedMinimumOS,
            sdk: encodedSDK
        )
        let delta = buildVersionCommand.count - versionCommandSize

        var patched = Data()
        patched.append(data.subdata(in: 0..<versionCommandOffset))
        patched.append(buildVersionCommand)
        patched.append(data.subdata(in: (versionCommandOffset + versionCommandSize)..<data.count))
        patched.writeUInt32(UInt32(sizeofCommands + delta), at: 20)

        commandOffset = 32
        for _ in 0..<commandCount {
            let command = patched.readUInt32(at: commandOffset)
            let commandSize = Int(patched.readUInt32(at: commandOffset + 4))
            if command == UInt32(LC_SEGMENT_64) {
                patched.addToUInt64IfNonZero(delta, at: commandOffset + 40)
                let sectionCount = Int(patched.readUInt32(at: commandOffset + 64))
                var sectionOffset = commandOffset + 72
                for _ in 0..<sectionCount {
                    patched.addToUInt32IfNonZero(delta, at: sectionOffset + 48)
                    patched.addToUInt32IfNonZero(delta, at: sectionOffset + 56)
                    sectionOffset += 80
                }
            } else if command == UInt32(LC_SYMTAB) {
                patched.addToUInt32IfNonZero(delta, at: commandOffset + 8)
                patched.addToUInt32IfNonZero(delta, at: commandOffset + 16)
            } else if command == UInt32(LC_DYSYMTAB) {
                [32, 40, 48, 56, 64, 72].forEach {
                    patched.addToUInt32IfNonZero(delta, at: commandOffset + $0)
                }
            } else if linkeditDataCommands.contains(command) {
                patched.addToUInt32IfNonZero(delta, at: commandOffset + 8)
            }
            commandOffset += commandSize
        }

        return patched
    }

    private func rebuildArchive(
        outputURL: URL,
        members: [String],
        patchedDirectory: URL
    ) throws {
        try archiveInspector.writeArchive(
            outputURL: outputURL,
            memberNames: members,
            sourceDirectoryURL: patchedDirectory
        )
    }

    private func rawValue(for platform: MachOPlatform) -> UInt32 {
        switch platform {
        case .macOS:
            return 1
        case .iOS:
            return 2
        case .tvOS:
            return 3
        case .watchOS:
            return 4
        case .bridgeOS:
            return 5
        case .macCatalyst:
            return 6
        case .iOSSimulator:
            return 7
        case .tvOSSimulator:
            return 8
        case .watchOSSimulator:
            return 9
        case .driverKit:
            return 10
        case .visionOS:
            return 11
        case .visionOSSimulator:
            return 12
        case .firmware:
            return 13
        case .sepOS:
            return 14
        case let .unknown(value):
            return value
        }
    }

    private func packedVersion(_ version: MachOVersion) -> UInt32 {
        UInt32(version.major << 16) | UInt32(version.minor << 8) | UInt32(version.patch)
    }

    private func buildVersionCommandData(
        platformRawValue: UInt32,
        minimumOS: UInt32,
        sdk: UInt32
    ) -> Data {
        var data = Data()
        [
            UInt32(LC_BUILD_VERSION),
            32,
            platformRawValue,
            minimumOS,
            sdk,
            1,
            3,
            0,
        ].forEach { value in
            var littleEndianValue = value.littleEndian
            Swift.withUnsafeBytes(of: &littleEndianValue) { rawBuffer in
                data.append(contentsOf: rawBuffer)
            }
        }
        return data
    }
}

private let supportedVersionCommands: Set<UInt32> = [
    UInt32(LC_VERSION_MIN_MACOSX),
    UInt32(LC_VERSION_MIN_IPHONEOS),
    UInt32(LC_VERSION_MIN_TVOS),
    UInt32(LC_VERSION_MIN_WATCHOS),
]

private let linkeditDataCommands: Set<UInt32> = [
    UInt32(LC_CODE_SIGNATURE),
    UInt32(LC_SEGMENT_SPLIT_INFO),
    UInt32(LC_FUNCTION_STARTS),
    UInt32(LC_DATA_IN_CODE),
    UInt32(LC_DYLIB_CODE_SIGN_DRS),
    UInt32(LC_LINKER_OPTIMIZATION_HINT),
    UInt32(LC_DYLD_EXPORTS_TRIE),
    UInt32(LC_DYLD_CHAINED_FIXUPS),
]

private extension Data {
    func readUInt32(at offset: Int) -> UInt32 {
        withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
    }

    func readUInt64(at offset: Int) -> UInt64 {
        withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
        }
    }

    mutating func writeUInt32(_ value: UInt32, at offset: Int) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { rawBuffer in
            replaceSubrange(offset..<(offset + rawBuffer.count), with: rawBuffer)
        }
    }

    mutating func writeUInt64(_ value: UInt64, at offset: Int) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { rawBuffer in
            replaceSubrange(offset..<(offset + rawBuffer.count), with: rawBuffer)
        }
    }

    mutating func addToUInt32IfNonZero(_ delta: Int, at offset: Int) {
        let current = readUInt32(at: offset)
        guard current != 0 else { return }
        writeUInt32(UInt32(Int(current) + delta), at: offset)
    }

    mutating func addToUInt64IfNonZero(_ delta: Int, at offset: Int) {
        let current = readUInt64(at: offset)
        guard current != 0 else { return }
        writeUInt64(UInt64(Int(current) + delta), at: offset)
    }
}

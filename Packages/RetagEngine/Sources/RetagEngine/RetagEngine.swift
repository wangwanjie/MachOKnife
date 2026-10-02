import CoreMachO
import Foundation
import MachO

public enum RetagEngineError: LocalizedError, Equatable {
    case architectureNotFound(String, available: [String])
    case byteSwappedArchiveMember(String)
    case malformedArchiveMember(String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .architectureNotFound(architecture, available):
            return "The file does not contain the architecture \(architecture). Available architectures: \(available.joined(separator: ", "))."
        case let .byteSwappedArchiveMember(member):
            return "Archive member \(member) is a byte-swapped (big-endian) Mach-O object, which cannot be retagged."
        case let .malformedArchiveMember(member, reason):
            return "Archive member \(member) is malformed: \(reason)"
        }
    }
}

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
        let platformEdit = try validatedPlatformEdit(platform: platform, minimumOS: minimumOS, sdk: sdk)
        if try archiveInspector.inspect(url: inputURL) != nil {
            let temporaryDirectory = try makeTemporaryDirectory(prefix: "MachOKnifeRetagPreview")
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
            let result = try retagArchive(
                inputURL: inputURL,
                outputURL: temporaryDirectory.appendingPathComponent("preview.a"),
                platformEdit: platformEdit,
                architecture: architecture
            )
            return RetagPreview(diff: result.diff)
        }
        let plan = try machOPlan(inputURL: inputURL, platformEdit: platformEdit, architecture: architecture)
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
        let platformEdit = try validatedPlatformEdit(platform: platform, minimumOS: minimumOS, sdk: sdk)
        if try archiveInspector.inspect(url: inputURL) != nil {
            return try retagArchive(
                inputURL: inputURL,
                outputURL: outputURL,
                platformEdit: platformEdit,
                architecture: architecture
            )
        }
        let plan = try machOPlan(inputURL: inputURL, platformEdit: platformEdit, architecture: architecture)
        let result = try writer.write(inputURL: inputURL, outputURL: outputURL, editPlan: plan)
        return RetagResult(outputURL: result.outputURL, diff: result.diff)
    }

    private func validatedPlatformEdit(platform: MachOPlatform, minimumOS: MachOVersion, sdk: MachOVersion) throws -> PlatformEdit {
        // Reject versions that cannot be encoded before any output is written.
        _ = try minimumOS.packedValue()
        _ = try sdk.packedValue()
        return PlatformEdit(platform: platform, minimumOS: minimumOS, sdk: sdk)
    }

    /// Builds the Mach-O edit plan, restricting it to the requested architecture's slice.
    private func machOPlan(inputURL: URL, platformEdit: PlatformEdit, architecture: String?) throws -> MachOEditPlan {
        guard let architecture else {
            return MachOEditPlan(platformEdit: platformEdit)
        }

        let container = try MachOContainer.parse(at: inputURL)
        let names = container.slices.map {
            MachOArchitectureNaming.name(cpuType: $0.header.cpuType, cpuSubtype: $0.header.cpuSubtype)
        }
        guard let index = names.firstIndex(of: architecture) else {
            throw RetagEngineError.architectureNotFound(architecture, available: names)
        }
        return MachOEditPlan(targetSliceOffset: container.slices[index].offset, platformEdit: platformEdit)
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
        platformEdit: PlatformEdit,
        architecture: String?
    ) throws -> RetagResult {
        let inspection = try archiveInspector.inspect(url: inputURL)
        let inputPermissions = MachOFileAttributes.posixPermissions(of: inputURL)

        let extraction = try archiveInspector.extractThinArchive(
            url: inputURL,
            preferredArchitecture: architecture
        )
        defer { try? FileManager.default.removeItem(at: extraction.archiveURL.deletingLastPathComponent()) }

        let workingDirectory = try makeTemporaryDirectory(prefix: "MachOKnifeArchiveRetag")
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        let extractedDirectory = workingDirectory.appendingPathComponent("members", isDirectory: true)
        let patchedDirectory = workingDirectory.appendingPathComponent("patched", isDirectory: true)
        try FileManager.default.createDirectory(at: patchedDirectory, withIntermediateDirectories: true)

        // Indexed extraction keeps members with duplicate names (common in static archives).
        let members = try archiveInspector.extractIndexedMembers(from: extraction.archiveURL, to: extractedDirectory)
            .filter { $0.isSymbolTable == false }

        var diffEntries = [DiffEntry]()
        var patchedMembers = [ArchiveMemberSource]()
        for member in members {
            let patchedMemberURL = patchedDirectory.appendingPathComponent(member.fileURL.lastPathComponent)
            let wasPatched = try patchArchiveMemberIfNeeded(
                memberName: member.name,
                sourceURL: member.fileURL,
                destinationURL: patchedMemberURL,
                platformEdit: platformEdit
            )
            patchedMembers.append(ArchiveMemberSource(name: member.name, fileURL: patchedMemberURL))
            if wasPatched {
                diffEntries.append(
                    DiffEntry(
                        sliceOffset: 0,
                        kind: .platform,
                        originalValue: member.name,
                        updatedValue: "\(member.name) -> \(platformEdit.platform) \(platformEdit.minimumOS) \(platformEdit.sdk)"
                    )
                )
            }
        }

        if inspection?.kind == .fatArchive {
            // Retag only the selected slice and keep every other architecture in the output.
            let thinOutputURL = workingDirectory.appendingPathComponent("retagged-\(extraction.architecture).a")
            try archiveInspector.writeArchive(outputURL: thinOutputURL, members: patchedMembers)
            try archiveInspector.rebuildFatArchive(
                from: inputURL,
                replacingArchitecture: extraction.architecture,
                withThinArchiveAt: thinOutputURL,
                outputURL: outputURL
            )
        } else {
            try archiveInspector.writeArchive(outputURL: outputURL, members: patchedMembers)
        }
        try MachOFileAttributes.setPosixPermissions(inputPermissions, on: outputURL)

        return RetagResult(outputURL: outputURL, diff: MachODiff(entries: diffEntries))
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func patchArchiveMemberIfNeeded(
        memberName: String,
        sourceURL: URL,
        destinationURL: URL,
        platformEdit: PlatformEdit
    ) throws -> Bool {
        let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        guard let patchedData = try patchedArchiveObjectData(
            memberName: memberName,
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

    /// Rewrites the platform of a thin, little-endian Mach-O object (32- or 64-bit).
    /// Returns nil for members that are not Mach-O objects or have no version command, so
    /// they are copied unchanged.
    func patchedArchiveObjectData(
        memberName: String,
        data: Data,
        targetPlatformRawValue: UInt32,
        minimumOS: MachOVersion,
        sdk: MachOVersion
    ) throws -> Data? {
        let data = Data(data)
        guard data.count >= 4 else { return nil }
        let magic = data.readUInt32(at: 0)
        if magic == MH_CIGAM || magic == MH_CIGAM_64 {
            throw RetagEngineError.byteSwappedArchiveMember(memberName)
        }
        guard magic == MH_MAGIC_64 || magic == MH_MAGIC else {
            return nil
        }

        let is64Bit = magic == MH_MAGIC_64
        let headerSize = is64Bit ? 32 : 28
        guard data.count >= headerSize else {
            throw RetagEngineError.malformedArchiveMember(memberName, reason: "the Mach-O header is truncated.")
        }
        guard data.readUInt32(at: 12) == UInt32(MH_OBJECT) else {
            return nil
        }

        func malformed(_ reason: String) -> RetagEngineError {
            .malformedArchiveMember(memberName, reason: reason)
        }

        let commandCount = Int(data.readUInt32(at: 16))
        let sizeofCommands = Int(data.readUInt32(at: 20))
        guard sizeofCommands <= data.count - headerSize else {
            throw malformed("sizeofcmds exceeds the file size.")
        }

        var commandOffset = headerSize
        var versionCommandOffset: Int?
        var versionCommandSize = 0
        var versionCommandKind: UInt32 = 0

        for _ in 0..<commandCount {
            guard commandOffset + 8 <= headerSize + sizeofCommands else {
                throw malformed("a load command extends past sizeofcmds.")
            }
            let command = data.readUInt32(at: commandOffset)
            let commandSize = Int(data.readUInt32(at: commandOffset + 4))
            guard commandSize >= 8, commandOffset + commandSize <= headerSize + sizeofCommands else {
                throw malformed("load command 0x\(String(command, radix: 16)) has an invalid size.")
            }

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

        let encodedMinimumOS = try minimumOS.packedValue()
        let encodedSDK = try sdk.packedValue()

        if versionCommandKind == UInt32(LC_BUILD_VERSION) {
            guard versionCommandSize >= 24 else {
                throw malformed("LC_BUILD_VERSION is truncated.")
            }
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

        // Everything after the load commands moved by `delta`; fix up file offsets.
        let segmentCommand = UInt32(is64Bit ? LC_SEGMENT_64 : LC_SEGMENT)
        let segmentFileOffsetField = is64Bit ? 40 : 32
        let sectionCountField = is64Bit ? 64 : 48
        let firstSectionOffset = is64Bit ? 72 : 56
        let sectionSize = is64Bit ? 80 : 68
        let sectionOffsetField = is64Bit ? 48 : 40
        let sectionRelocationOffsetField = is64Bit ? 56 : 48
        let commandsEnd = headerSize + sizeofCommands + delta

        commandOffset = headerSize
        for _ in 0..<commandCount {
            guard commandOffset + 8 <= commandsEnd else {
                throw malformed("a load command extends past sizeofcmds.")
            }
            let command = patched.readUInt32(at: commandOffset)
            let commandSize = Int(patched.readUInt32(at: commandOffset + 4))
            guard commandSize >= 8, commandOffset + commandSize <= commandsEnd else {
                throw malformed("load command 0x\(String(command, radix: 16)) has an invalid size.")
            }

            func requireFields(through end: Int) throws {
                guard end <= commandSize else {
                    throw malformed("load command 0x\(String(command, radix: 16)) is truncated.")
                }
            }

            if command == segmentCommand {
                try requireFields(through: firstSectionOffset)
                if is64Bit {
                    try patched.addToUInt64IfNonZero(delta, at: commandOffset + segmentFileOffsetField)
                } else {
                    try patched.addToUInt32IfNonZero(delta, at: commandOffset + segmentFileOffsetField)
                }
                let sectionCount = Int(patched.readUInt32(at: commandOffset + sectionCountField))
                guard sectionCount <= (commandSize - firstSectionOffset) / sectionSize else {
                    throw malformed("segment section count exceeds its load command.")
                }
                var sectionOffset = commandOffset + firstSectionOffset
                for _ in 0..<sectionCount {
                    try patched.addToUInt32IfNonZero(delta, at: sectionOffset + sectionOffsetField)
                    try patched.addToUInt32IfNonZero(delta, at: sectionOffset + sectionRelocationOffsetField)
                    sectionOffset += sectionSize
                }
            } else if command == UInt32(LC_SYMTAB) {
                try requireFields(through: 24)
                try patched.addToUInt32IfNonZero(delta, at: commandOffset + 8)
                try patched.addToUInt32IfNonZero(delta, at: commandOffset + 16)
            } else if command == UInt32(LC_DYSYMTAB) {
                try requireFields(through: 80)
                for field in [32, 40, 48, 56, 64, 72] {
                    try patched.addToUInt32IfNonZero(delta, at: commandOffset + field)
                }
            } else if linkeditDataCommands.contains(command) {
                try requireFields(through: 16)
                try patched.addToUInt32IfNonZero(delta, at: commandOffset + 8)
            }
            commandOffset += commandSize
        }

        return patched
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

    mutating func addToUInt32IfNonZero(_ delta: Int, at offset: Int) throws {
        let current = readUInt32(at: offset)
        guard current != 0 else { return }
        guard let updated = UInt32(exactly: Int(current) + delta) else {
            throw RetagEngineError.malformedArchiveMember("object", reason: "a file offset overflows after inserting LC_BUILD_VERSION.")
        }
        writeUInt32(updated, at: offset)
    }

    mutating func addToUInt64IfNonZero(_ delta: Int, at offset: Int) throws {
        let current = readUInt64(at: offset)
        guard current != 0 else { return }
        guard let base = Int(exactly: current), let updated = UInt64(exactly: base + delta) else {
            throw RetagEngineError.malformedArchiveMember("object", reason: "a file offset overflows after inserting LC_BUILD_VERSION.")
        }
        writeUInt64(updated, at: offset)
    }
}

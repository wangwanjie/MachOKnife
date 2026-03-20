import CoreMachOC
import Foundation

public enum MachOWriteError: Error {
    case missingSlicePayloadBoundary(Int)
    case insufficientLoadCommandSpace(required: Int, available: Int, sliceOffset: Int)
    case unsupportedVersionCommand(UInt32)
}

public struct MachOWriter: Sendable {
    public init() {}

    public func write(inputURL: URL, outputURL: URL, editPlan: MachOEditPlan) throws -> MachOWriteResult {
        let originalData = try Data(contentsOf: inputURL, options: [.mappedIfSafe])
        let container = try MachOContainer.parse(at: inputURL)
        var rewrittenData = originalData
        var diffEntries = [DiffEntry]()
        var removedCodeSignature = false

        for slice in container.slices {
            let rewrite = try rewriteSlice(slice, in: originalData, plan: editPlan)
            rewrittenData.replaceSubrange(rewrite.commandAreaRange, with: rewrite.commandAreaData)
            patchHeader(in: &rewrittenData, slice: slice, commandCount: rewrite.commandCount, sizeofCommands: rewrite.sizeofCommands)
            diffEntries.append(contentsOf: rewrite.diffEntries)
            removedCodeSignature = removedCodeSignature || rewrite.removedCodeSignature
        }

        try rewrittenData.write(to: outputURL, options: [.atomic])
        return MachOWriteResult(outputURL: outputURL, diff: MachODiff(entries: diffEntries), removedCodeSignature: removedCodeSignature)
    }

    private func rewriteSlice(_ slice: MachOSlice, in data: Data, plan: MachOEditPlan) throws -> SliceRewriteResult {
        let headerSize = slice.header.is64Bit ? MemoryLayout<mach_header_64>.size : MemoryLayout<mach_header>.size
        let commandsStart = slice.offset + headerSize
        let availableCommandBytes = try availableLoadCommandBytes(for: slice)
        let commandAreaRange = commandsStart..<(commandsStart + availableCommandBytes)

        var rewrittenCommands = [Data]()
        rewrittenCommands.reserveCapacity(slice.loadCommands.count + plan.rpathEdits.count + plan.dylibEdits.count)
        var diffEntries = [DiffEntry]()

        let segmentProtectionMap = Dictionary(
            uniqueKeysWithValues: plan.segmentProtectionEdits.map { ($0.segmentName, $0) }
        )
        let shouldRemoveCodeSignature = plan.stripCodeSignature || editPlanTouchesSignedMetadata(plan)

        var usedDylibReplaceIndexes = Set<Int>()
        var usedDylibRemoveIndexes = Set<Int>()
        var usedRPathReplaceIndexes = Set<Int>()
        var usedRPathRemoveIndexes = Set<Int>()

        for command in slice.loadCommands {
            let rawData = data.subdata(in: command.offset..<(command.offset + Int(command.size)))

            switch command.payload {
            case let .dylib(info)?:
                if command.command == UInt32(LC_ID_DYLIB) {
                    if let installName = plan.installName, installName != info.path {
                        rewrittenCommands.append(serializeDylibCommand(command: info.command, path: installName, from: info, is64Bit: slice.is64Bit))
                        diffEntries.append(
                            DiffEntry(sliceOffset: slice.offset, kind: .installName, originalValue: info.path, updatedValue: installName)
                        )
                    } else {
                        rewrittenCommands.append(rawData)
                    }
                    continue
                }

                if let replacement = matchDylibReplacement(for: info, edits: plan.dylibEdits, usedIndexes: &usedDylibReplaceIndexes) {
                    rewrittenCommands.append(serializeDylibCommand(command: info.command, path: replacement.newPath, from: info, is64Bit: slice.is64Bit))
                    diffEntries.append(
                        DiffEntry(sliceOffset: slice.offset, kind: .dylib, originalValue: info.path, updatedValue: replacement.newPath)
                    )
                    continue
                }

                if matchDylibRemoval(for: info, edits: plan.dylibEdits, usedIndexes: &usedDylibRemoveIndexes) {
                    diffEntries.append(
                        DiffEntry(sliceOffset: slice.offset, kind: .dylib, originalValue: info.path, updatedValue: nil)
                    )
                    continue
                }

                rewrittenCommands.append(rawData)
            case let .rpath(info)?:
                if let replacement = matchRPathReplacement(for: info.path, edits: plan.rpathEdits, usedIndexes: &usedRPathReplaceIndexes) {
                    rewrittenCommands.append(serializeRPathCommand(path: replacement, is64Bit: slice.is64Bit))
                    diffEntries.append(
                        DiffEntry(sliceOffset: slice.offset, kind: .rpath, originalValue: info.path, updatedValue: replacement)
                    )
                    continue
                }

                if matchRPathRemoval(for: info.path, edits: plan.rpathEdits, usedIndexes: &usedRPathRemoveIndexes) {
                    diffEntries.append(
                        DiffEntry(sliceOffset: slice.offset, kind: .rpath, originalValue: info.path, updatedValue: nil)
                    )
                    continue
                }

                rewrittenCommands.append(rawData)
            case let .buildVersion(info)?:
                if let platformEdit = plan.platformEdit {
                    rewrittenCommands.append(serializeBuildVersionCommand(info: info, edit: platformEdit, is64Bit: slice.is64Bit))
                    diffEntries.append(
                        DiffEntry(
                            sliceOffset: slice.offset,
                            kind: .platform,
                            originalValue: "\(info.platform) \(info.minimumOS) \(info.sdk)",
                            updatedValue: "\(platformEdit.platform) \(platformEdit.minimumOS) \(platformEdit.sdk)"
                        )
                    )
                } else {
                    rewrittenCommands.append(rawData)
                }
            case let .versionMin(info)?:
                if let platformEdit = plan.platformEdit {
                    rewrittenCommands.append(try serializeVersionMinCommand(info: info, edit: platformEdit, is64Bit: slice.is64Bit))
                    diffEntries.append(
                        DiffEntry(
                            sliceOffset: slice.offset,
                            kind: .platform,
                            originalValue: "\(info.platform) \(info.minimumOS) \(info.sdk)",
                            updatedValue: "\(platformEdit.platform) \(platformEdit.minimumOS) \(platformEdit.sdk)"
                        )
                    )
                } else {
                    rewrittenCommands.append(rawData)
                }
            case let .segment(info)?:
                if let edit = segmentProtectionMap[info.name] {
                    rewrittenCommands.append(serializeSegmentCommand(original: rawData, segment: info, edit: edit))
                    diffEntries.append(
                        DiffEntry(
                            sliceOffset: slice.offset,
                            kind: .segmentProtection,
                            originalValue: "\(info.name) max=\(info.maxProtection.rawValue) init=\(info.initialProtection.rawValue)",
                            updatedValue: "\(info.name) max=\((edit.maxProtection ?? info.maxProtection).rawValue) init=\((edit.initialProtection ?? info.initialProtection).rawValue)"
                        )
                    )
                } else {
                    rewrittenCommands.append(rawData)
                }
            case .codeSignature?:
                if shouldRemoveCodeSignature {
                    diffEntries.append(
                        DiffEntry(sliceOffset: slice.offset, kind: .codeSignature, originalValue: "present", updatedValue: "removed")
                    )
                } else {
                    rewrittenCommands.append(rawData)
                }
            default:
                rewrittenCommands.append(rawData)
            }
        }

        for edit in plan.dylibEdits {
            guard case let .add(path, command) = edit else { continue }
            let template = slice.dylibReferences.first(where: { $0.command == command }) ?? slice.dylibReferences.first
            let serialized = serializeDylibCommand(command: command, path: path, from: template, is64Bit: slice.is64Bit)
            rewrittenCommands.append(serialized)
            diffEntries.append(DiffEntry(sliceOffset: slice.offset, kind: .dylib, originalValue: nil, updatedValue: path))
        }

        for edit in plan.rpathEdits {
            guard case let .add(path) = edit else { continue }
            rewrittenCommands.append(serializeRPathCommand(path: path, is64Bit: slice.is64Bit))
            diffEntries.append(DiffEntry(sliceOffset: slice.offset, kind: .rpath, originalValue: nil, updatedValue: path))
        }

        if let platformEdit = plan.platformEdit, slice.buildVersion == nil, slice.versionMin == nil {
            rewrittenCommands.append(serializeBuildVersionCommand(edit: platformEdit, is64Bit: slice.is64Bit))
            diffEntries.append(
                DiffEntry(
                    sliceOffset: slice.offset,
                    kind: .platform,
                    originalValue: nil,
                    updatedValue: "\(platformEdit.platform) \(platformEdit.minimumOS) \(platformEdit.sdk)"
                )
            )
        }

        let serializedCommandBytes = rewrittenCommands.reduce(into: Data(), { $0.append($1) })
        let requiredBytes = serializedCommandBytes.count
        guard requiredBytes <= availableCommandBytes else {
            throw MachOWriteError.insufficientLoadCommandSpace(
                required: requiredBytes,
                available: availableCommandBytes,
                sliceOffset: slice.offset
            )
        }

        var commandAreaData = Data(count: availableCommandBytes)
        commandAreaData.replaceSubrange(0..<requiredBytes, with: serializedCommandBytes)

        return SliceRewriteResult(
            commandAreaRange: commandAreaRange,
            commandAreaData: commandAreaData,
            commandCount: UInt32(rewrittenCommands.count),
            sizeofCommands: UInt32(requiredBytes),
            diffEntries: diffEntries,
            removedCodeSignature: shouldRemoveCodeSignature && slice.codeSignature != nil
        )
    }

    private func patchHeader(in data: inout Data, slice: MachOSlice, commandCount: UInt32, sizeofCommands: UInt32) {
        if slice.header.is64Bit {
            var header = data.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: slice.offset, as: mach_header_64.self)
            }
            header.ncmds = commandCount
            header.sizeofcmds = sizeofCommands
            writeStruct(header, into: &data, at: slice.offset)
        } else {
            var header = data.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: slice.offset, as: mach_header.self)
            }
            header.ncmds = commandCount
            header.sizeofcmds = sizeofCommands
            writeStruct(header, into: &data, at: slice.offset)
        }
    }

    private func availableLoadCommandBytes(for slice: MachOSlice) throws -> Int {
        let headerSize = slice.header.is64Bit ? MemoryLayout<mach_header_64>.size : MemoryLayout<mach_header>.size

        let sectionOffsets = slice.segments
            .flatMap(\.sections)
            .map(\.fileOffset)
            .filter { $0 > 0 }
            .map(Int.init)

        let segmentOffsets = slice.segments
            .map(\.fileOffset)
            .filter { $0 > 0 }
            .map(Int.init)

        let payloadStart = (sectionOffsets + segmentOffsets).min()
        guard let payloadStart else {
            throw MachOWriteError.missingSlicePayloadBoundary(slice.offset)
        }

        return payloadStart - headerSize
    }

    private func editPlanTouchesSignedMetadata(_ plan: MachOEditPlan) -> Bool {
        plan.installName != nil
            || plan.dylibEdits.isEmpty == false
            || plan.rpathEdits.isEmpty == false
            || plan.platformEdit != nil
            || plan.segmentProtectionEdits.isEmpty == false
    }

    private func matchDylibReplacement(
        for info: DylibCommandInfo,
        edits: [DylibEdit],
        usedIndexes: inout Set<Int>
    ) -> (index: Int, newPath: String)? {
        for (index, edit) in edits.enumerated() {
            guard usedIndexes.contains(index) == false else { continue }
            guard case let .replace(oldPath, newPath, command) = edit else { continue }
            guard oldPath == info.path else { continue }
            guard command == nil || command == info.command else { continue }
            usedIndexes.insert(index)
            return (index, newPath)
        }

        return nil
    }

    private func matchDylibRemoval(
        for info: DylibCommandInfo,
        edits: [DylibEdit],
        usedIndexes: inout Set<Int>
    ) -> Bool {
        for (index, edit) in edits.enumerated() {
            guard usedIndexes.contains(index) == false else { continue }
            guard case let .remove(path, command) = edit else { continue }
            guard path == info.path else { continue }
            guard command == nil || command == info.command else { continue }
            usedIndexes.insert(index)
            return true
        }

        return false
    }

    private func matchRPathReplacement(
        for path: String,
        edits: [RPathEdit],
        usedIndexes: inout Set<Int>
    ) -> String? {
        for (index, edit) in edits.enumerated() {
            guard usedIndexes.contains(index) == false else { continue }
            guard case let .replace(oldPath, newPath) = edit else { continue }
            guard oldPath == path else { continue }
            usedIndexes.insert(index)
            return newPath
        }

        return nil
    }

    private func matchRPathRemoval(
        for path: String,
        edits: [RPathEdit],
        usedIndexes: inout Set<Int>
    ) -> Bool {
        for (index, edit) in edits.enumerated() {
            guard usedIndexes.contains(index) == false else { continue }
            guard case let .remove(oldPath) = edit else { continue }
            guard oldPath == path else { continue }
            usedIndexes.insert(index)
            return true
        }

        return false
    }

    private func serializeDylibCommand(command: UInt32, path: String, from template: DylibCommandInfo?, is64Bit: Bool) -> Data {
        let alignment = is64Bit ? 8 : 4
        let pathData = utf8CStringData(path)
        let commandSize = alignedSize(MemoryLayout<dylib_command>.size + pathData.count, alignment: alignment)

        var dylibCommand = dylib_command()
        dylibCommand.cmd = command
        dylibCommand.cmdsize = UInt32(commandSize)
        dylibCommand.dylib.name.offset = UInt32(MemoryLayout<dylib_command>.size)
        dylibCommand.dylib.timestamp = template?.timestamp ?? 0
        dylibCommand.dylib.current_version = packedVersion(template?.currentVersion ?? MachOVersion(major: 1, minor: 0, patch: 0))
        dylibCommand.dylib.compatibility_version = packedVersion(template?.compatibilityVersion ?? MachOVersion(major: 1, minor: 0, patch: 0))

        var data = Data()
        appendStruct(dylibCommand, to: &data)
        data.append(pathData)
        if data.count < commandSize {
            data.append(Data(count: commandSize - data.count))
        }
        return data
    }

    private func serializeRPathCommand(path: String, is64Bit: Bool) -> Data {
        let alignment = is64Bit ? 8 : 4
        let pathData = utf8CStringData(path)
        let commandSize = alignedSize(MemoryLayout<rpath_command>.size + pathData.count, alignment: alignment)

        var command = rpath_command()
        command.cmd = UInt32(LC_RPATH)
        command.cmdsize = UInt32(commandSize)
        command.path.offset = UInt32(MemoryLayout<rpath_command>.size)

        var data = Data()
        appendStruct(command, to: &data)
        data.append(pathData)
        if data.count < commandSize {
            data.append(Data(count: commandSize - data.count))
        }
        return data
    }

    private func serializeBuildVersionCommand(info: BuildVersionInfo, edit: PlatformEdit, is64Bit: Bool) -> Data {
        serializeBuildVersionCommand(
            command: info.command,
            platform: edit.platform,
            minimumOS: edit.minimumOS,
            sdk: edit.sdk,
            tools: info.tools,
            is64Bit: is64Bit
        )
    }

    private func serializeBuildVersionCommand(edit: PlatformEdit, is64Bit: Bool) -> Data {
        serializeBuildVersionCommand(
            command: UInt32(LC_BUILD_VERSION),
            platform: edit.platform,
            minimumOS: edit.minimumOS,
            sdk: edit.sdk,
            tools: [],
            is64Bit: is64Bit
        )
    }

    private func serializeBuildVersionCommand(
        command: UInt32,
        platform: MachOPlatform,
        minimumOS: MachOVersion,
        sdk: MachOVersion,
        tools: [BuildToolVersionInfo],
        is64Bit: Bool
    ) -> Data {
        let alignment = is64Bit ? 8 : 4
        let totalSize = alignedSize(
            MemoryLayout<build_version_command>.size + tools.count * MemoryLayout<build_tool_version>.size,
            alignment: alignment
        )

        var buildVersionCommand = build_version_command()
        buildVersionCommand.cmd = command
        buildVersionCommand.cmdsize = UInt32(totalSize)
        buildVersionCommand.platform = rawValue(for: platform)
        buildVersionCommand.minos = packedVersion(minimumOS)
        buildVersionCommand.sdk = packedVersion(sdk)
        buildVersionCommand.ntools = UInt32(tools.count)

        var data = Data()
        appendStruct(buildVersionCommand, to: &data)
        for tool in tools {
            var toolVersion = build_tool_version()
            toolVersion.tool = tool.tool
            toolVersion.version = packedVersion(tool.version)
            appendStruct(toolVersion, to: &data)
        }
        if data.count < totalSize {
            data.append(Data(count: totalSize - data.count))
        }
        return data
    }

    private func serializeVersionMinCommand(info: VersionMinInfo, edit: PlatformEdit, is64Bit: Bool) throws -> Data {
        let command = switch edit.platform {
        case .macOS:
            UInt32(LC_VERSION_MIN_MACOSX)
        case .iOS:
            UInt32(LC_VERSION_MIN_IPHONEOS)
        case .tvOS:
            UInt32(LC_VERSION_MIN_TVOS)
        case .watchOS:
            UInt32(LC_VERSION_MIN_WATCHOS)
        default:
            throw MachOWriteError.unsupportedVersionCommand(info.command)
        }

        let alignment = is64Bit ? 8 : 4
        let totalSize = alignedSize(MemoryLayout<version_min_command>.size, alignment: alignment)

        var versionCommand = version_min_command()
        versionCommand.cmd = command
        versionCommand.cmdsize = UInt32(totalSize)
        versionCommand.version = packedVersion(edit.minimumOS)
        versionCommand.sdk = packedVersion(edit.sdk)

        var data = Data()
        appendStruct(versionCommand, to: &data)
        if data.count < totalSize {
            data.append(Data(count: totalSize - data.count))
        }
        return data
    }

    private func serializeSegmentCommand(original: Data, segment: SegmentInfo, edit: SegmentProtectionEdit) -> Data {
        var data = original
        if segment.command == UInt32(LC_SEGMENT_64) {
            var command = original.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: 0, as: segment_command_64.self)
            }
            if let maxProtection = edit.maxProtection {
                command.maxprot = maxProtection.rawValue
            }
            if let initialProtection = edit.initialProtection {
                command.initprot = initialProtection.rawValue
            }
            writeStruct(command, into: &data, at: 0)
        } else {
            var command = original.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: 0, as: segment_command.self)
            }
            if let maxProtection = edit.maxProtection {
                command.maxprot = maxProtection.rawValue
            }
            if let initialProtection = edit.initialProtection {
                command.initprot = initialProtection.rawValue
            }
            writeStruct(command, into: &data, at: 0)
        }
        return data
    }

    private func alignedSize(_ value: Int, alignment: Int) -> Int {
        let remainder = value % alignment
        return remainder == 0 ? value : value + alignment - remainder
    }

    private func packedVersion(_ version: MachOVersion) -> UInt32 {
        UInt32(version.major << 16) | UInt32(version.minor << 8) | UInt32(version.patch)
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

    private func utf8CStringData(_ string: String) -> Data {
        Data(string.utf8) + Data([0])
    }

    private func appendStruct<T>(_ value: T, to data: inout Data) {
        var mutableValue = value
        withUnsafeBytes(of: &mutableValue) { rawBuffer in
            data.append(contentsOf: rawBuffer)
        }
    }

    private func writeStruct<T>(_ value: T, into data: inout Data, at offset: Int) {
        var mutableValue = value
        withUnsafeBytes(of: &mutableValue) { rawBuffer in
            data.replaceSubrange(offset..<(offset + rawBuffer.count), with: rawBuffer)
        }
    }
}

private struct SliceRewriteResult {
    let commandAreaRange: Range<Int>
    let commandAreaData: Data
    let commandCount: UInt32
    let sizeofCommands: UInt32
    let diffEntries: [DiffEntry]
    let removedCodeSignature: Bool
}

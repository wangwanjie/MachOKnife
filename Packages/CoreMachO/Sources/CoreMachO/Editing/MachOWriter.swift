import CoreMachOC
import Foundation

public enum MachOWriteError: LocalizedError {
    case missingSlicePayloadBoundary(Int)
    case insufficientLoadCommandSpace(required: Int, available: Int, sliceOffset: Int)
    case unsupportedVersionCommand(UInt32)
    case byteSwappedSliceUnsupported(sliceOffset: Int)
    case missingInstallNameCommand(sliceOffset: Int)
    case malformedLoadCommandArea(sliceOffset: Int, reason: String)
    case invalidVersion(MachOVersion)

    public var errorDescription: String? {
        switch self {
        case let .missingSlicePayloadBoundary(sliceOffset):
            return "Could not determine where the load command area ends for the slice at offset \(sliceOffset)."
        case let .insufficientLoadCommandSpace(required, available, sliceOffset):
            return "The slice at offset \(sliceOffset) needs \(required) bytes of load commands but only \(available) bytes are available."
        case let .unsupportedVersionCommand(command):
            return "Unsupported version command 0x\(String(command, radix: 16))."
        case let .byteSwappedSliceUnsupported(sliceOffset):
            return "The slice at offset \(sliceOffset) is byte-swapped (big-endian); editing byte-swapped Mach-O files is not supported."
        case let .missingInstallNameCommand(sliceOffset):
            return "The slice at offset \(sliceOffset) has no LC_ID_DYLIB command, so its install name cannot be changed."
        case let .malformedLoadCommandArea(sliceOffset, reason):
            return "The load command area of the slice at offset \(sliceOffset) is malformed: \(reason)"
        case let .invalidVersion(version):
            return "Version \(version) cannot be encoded: major must be 0...65535 and minor/patch must be 0...255."
        }
    }
}

public struct MachOWriter: Sendable {
    public init() {}

    public func preview(inputURL: URL, editPlan: MachOEditPlan) throws -> MachODiff {
        let originalData = try Data(contentsOf: inputURL, options: [.mappedIfSafe])
        let container = try MachOContainer.parse(at: inputURL)
        let diffEntries = try container.slices.flatMap { slice in
            guard applies(editPlan, to: slice) else {
                return [DiffEntry]()
            }
            // 预览不修改文件，切片大小只影响签名裁剪，这里传入 0 表示不计算裁剪。
            return try rewriteSlice(slice, in: originalData, plan: editPlan, sliceSize: 0).diffEntries
        }
        return MachODiff(entries: diffEntries)
    }

    public func write(inputURL: URL, outputURL: URL, editPlan: MachOEditPlan) throws -> MachOWriteResult {
        let originalData = try Data(contentsOf: inputURL, options: [.mappedIfSafe])
        let container = try MachOContainer.parse(at: inputURL)
        var rewrittenData = originalData
        var diffEntries = [DiffEntry]()
        var removedCodeSignature = false
        // fat 文件需要在裁剪签名后同步更新 fat_arch.size。
        let fatEntries = container.kind == .fat ? try MachOFileParser(data: originalData).fatArchitectureEntries() : []
        var truncatedFileSize: Int?

        for slice in container.slices {
            guard applies(editPlan, to: slice) else {
                continue
            }
            let fatEntry = fatEntries.first(where: { $0.offset == slice.offset })
            let sliceSize = sliceByteCount(slice, fatEntry: fatEntry, fileSize: originalData.count)
            let rewrite = try rewriteSlice(slice, in: originalData, plan: editPlan, sliceSize: sliceSize)
            rewrittenData.replaceSubrange(rewrite.commandAreaRange, with: rewrite.commandAreaData)
            patchHeader(in: &rewrittenData, slice: slice, commandCount: rewrite.commandCount, sizeofCommands: rewrite.sizeofCommands)
            diffEntries.append(contentsOf: rewrite.diffEntries)
            removedCodeSignature = removedCodeSignature || rewrite.removedCodeSignature

            // 与 `codesign --remove-signature` 一致：签名数据位于切片末尾时把它从文件中去掉，
            // 否则旧签名会作为垃圾数据留在 __LINKEDIT 末尾，重新签名后文件持续变大。
            if let trimmedSliceSize = rewrite.trimmedSliceSize {
                let freedRange = (slice.offset + trimmedSliceSize)..<(slice.offset + sliceSize)
                rewrittenData.resetBytes(in: freedRange)
                if let fatEntry {
                    patchFatSliceSize(in: &rewrittenData, entry: fatEntry, newSize: trimmedSliceSize)
                }
                if freedRange.upperBound == originalData.count {
                    truncatedFileSize = freedRange.lowerBound
                }
            }
        }

        if let truncatedFileSize {
            rewrittenData.removeSubrange(truncatedFileSize..<rewrittenData.count)
        }

        let inputPermissions = MachOFileAttributes.posixPermissions(of: inputURL)
        try rewrittenData.write(to: outputURL, options: [.atomic])
        try MachOFileAttributes.setPosixPermissions(inputPermissions, on: outputURL)
        return MachOWriteResult(outputURL: outputURL, diff: MachODiff(entries: diffEntries), removedCodeSignature: removedCodeSignature)
    }

    private func applies(_ plan: MachOEditPlan, to slice: MachOSlice) -> Bool {
        plan.targetSliceOffset == nil || plan.targetSliceOffset == slice.offset
    }

    /// 计算切片的字节数：fat 切片取 fat_arch.size（限制在文件范围内），thin 文件取整个文件。
    private func sliceByteCount(_ slice: MachOSlice, fatEntry: FatArchitectureEntry?, fileSize: Int) -> Int {
        let remaining = max(0, fileSize - slice.offset)
        guard let fatEntry else {
            return remaining
        }
        return min(Int(clamping: fatEntry.size), remaining)
    }

    private func rewriteSlice(_ slice: MachOSlice, in data: Data, plan: MachOEditPlan, sliceSize: Int) throws -> SliceRewriteResult {
        try ensureNativeByteOrder(slice, in: data)
        if plan.installName != nil, slice.installNameInfo == nil {
            throw MachOWriteError.missingInstallNameCommand(sliceOffset: slice.offset)
        }

        let headerSize = slice.header.is64Bit ? MemoryLayout<mach_header_64>.size : MemoryLayout<mach_header>.size
        let commandsStart = slice.offset + headerSize
        let availableCommandBytes = try availableLoadCommandBytes(for: slice, fileSize: data.count)
        let commandAreaRange = commandsStart..<(commandsStart + availableCommandBytes)

        var rewrittenCommands = [Data]()
        rewrittenCommands.reserveCapacity(slice.loadCommands.count + plan.rpathEdits.count + plan.dylibEdits.count)
        var diffEntries = [DiffEntry]()

        // 同一段名出现多次时以最后一个编辑为准；以前用 uniqueKeysWithValues，重复段名会直接触发运行时崩溃。
        let segmentProtectionMap = Dictionary(
            plan.segmentProtectionEdits.map { ($0.segmentName, $0) },
            uniquingKeysWith: { _, last in
                last
            }
        )
        // LC_CODE_SIGNATURE 是否移除要等所有编辑处理完后再决定：只有显式要求剥离签名，
        // 或确实产生了修改时才移除；以前只要计划里带了编辑项（即使没有匹配、文件未变）也会删掉签名。
        var codeSignatureCommandIndex: Int?
        var linkEditCommandIndex: Int?
        // 平台编辑时只保留一条 LC_BUILD_VERSION：zippered 等含多条版本命令的文件，
        // 全部改写成同一平台会产生重复的 LC_BUILD_VERSION，dyld 会拒绝加载。
        var wroteBuildVersion = false

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
                        rewrittenCommands.append(try serializeDylibCommand(
                            command: info.command,
                            path: installName,
                            timestamp: info.timestamp,
                            currentVersion: info.currentVersion,
                            compatibilityVersion: info.compatibilityVersion,
                            is64Bit: slice.is64Bit
                        ))
                        diffEntries.append(
                            DiffEntry(sliceOffset: slice.offset, kind: .installName, originalValue: info.path, updatedValue: installName)
                        )
                    } else {
                        rewrittenCommands.append(rawData)
                    }
                    continue
                }

                if let replacement = matchDylibReplacement(for: info, edits: plan.dylibEdits, usedIndexes: &usedDylibReplaceIndexes) {
                    rewrittenCommands.append(try serializeDylibCommand(
                        command: info.command,
                        path: replacement.newPath,
                        timestamp: info.timestamp,
                        currentVersion: info.currentVersion,
                        compatibilityVersion: info.compatibilityVersion,
                        is64Bit: slice.is64Bit
                    ))
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
                    if wroteBuildVersion {
                        diffEntries.append(
                            DiffEntry(
                                sliceOffset: slice.offset,
                                kind: .platform,
                                originalValue: "\(info.platform) \(info.minimumOS) \(info.sdk)",
                                updatedValue: nil
                            )
                        )
                        continue
                    }
                    wroteBuildVersion = true
                    rewrittenCommands.append(try serializeBuildVersionCommand(info: info, edit: platformEdit, is64Bit: slice.is64Bit))
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
                    if usesBuildVersionCommand(for: platformEdit.platform) {
                        // 已有（或即将写入）LC_BUILD_VERSION 时直接丢弃旧的 version-min，避免出现重复的版本命令。
                        if wroteBuildVersion || slice.buildVersion != nil {
                            diffEntries.append(
                                DiffEntry(
                                    sliceOffset: slice.offset,
                                    kind: .platform,
                                    originalValue: "\(info.platform) \(info.minimumOS) \(info.sdk)",
                                    updatedValue: nil
                                )
                            )
                            continue
                        }
                        wroteBuildVersion = true
                        rewrittenCommands.append(
                            try serializeBuildVersionCommand(
                                command: UInt32(LC_BUILD_VERSION),
                                platform: platformEdit.platform,
                                minimumOS: platformEdit.minimumOS,
                                sdk: platformEdit.sdk,
                                tools: [],
                                is64Bit: slice.is64Bit
                            )
                        )
                    } else {
                        rewrittenCommands.append(try serializeVersionMinCommand(info: info, edit: platformEdit, is64Bit: slice.is64Bit))
                    }
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
                if info.name == SEG_LINKEDIT {
                    linkEditCommandIndex = rewrittenCommands.count
                }
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
                // 先保留，待所有编辑处理完后再决定是否移除。
                codeSignatureCommandIndex = rewrittenCommands.count
                rewrittenCommands.append(rawData)
            default:
                rewrittenCommands.append(rawData)
            }
        }

        for edit in plan.dylibEdits {
            guard case let .add(path, command, currentVersion, compatibilityVersion) = edit else { continue }
            // New dylib commands must not inherit metadata from unrelated dylibs: use the
            // conventional timestamp 2 and the requested versions (0.0.0 when unspecified).
            let zeroVersion = MachOVersion(major: 0, minor: 0, patch: 0)
            let serialized = try serializeDylibCommand(
                command: command,
                path: path,
                timestamp: 2,
                currentVersion: currentVersion ?? zeroVersion,
                compatibilityVersion: compatibilityVersion ?? zeroVersion,
                is64Bit: slice.is64Bit
            )
            rewrittenCommands.append(serialized)
            diffEntries.append(DiffEntry(sliceOffset: slice.offset, kind: .dylib, originalValue: nil, updatedValue: path))
        }

        for edit in plan.rpathEdits {
            guard case let .add(path) = edit else { continue }
            rewrittenCommands.append(serializeRPathCommand(path: path, is64Bit: slice.is64Bit))
            diffEntries.append(DiffEntry(sliceOffset: slice.offset, kind: .rpath, originalValue: nil, updatedValue: path))
        }

        if let platformEdit = plan.platformEdit, slice.buildVersion == nil, slice.versionMin == nil {
            rewrittenCommands.append(try serializeBuildVersionCommand(edit: platformEdit, is64Bit: slice.is64Bit))
            diffEntries.append(
                DiffEntry(
                    sliceOffset: slice.offset,
                    kind: .platform,
                    originalValue: nil,
                    updatedValue: "\(platformEdit.platform) \(platformEdit.minimumOS) \(platformEdit.sdk)"
                )
            )
        }

        // 有实际修改（diffEntries 非空）或显式要求时才移除签名：修改后的文件签名必然失效。
        let shouldRemoveCodeSignature = plan.stripCodeSignature || diffEntries.isEmpty == false
        var trimmedSliceSize: Int?
        if shouldRemoveCodeSignature, let codeSignatureCommandIndex {
            rewrittenCommands.remove(at: codeSignatureCommandIndex)
            diffEntries.append(
                DiffEntry(sliceOffset: slice.offset, kind: .codeSignature, originalValue: "present", updatedValue: "removed")
            )
            if let linkEditIndex = linkEditCommandIndex {
                // __LINKEDIT 位于签名命令之后时，删除签名命令会让它的下标前移一位。
                let adjustedIndex = linkEditIndex > codeSignatureCommandIndex ? linkEditIndex - 1 : linkEditIndex
                if let trim = codeSignatureTrim(for: slice, sliceSize: sliceSize) {
                    rewrittenCommands[adjustedIndex] = shrinkLinkEditSegment(
                        rewrittenCommands[adjustedIndex],
                        newFileSize: trim.linkEditFileSize
                    )
                    trimmedSliceSize = trim.sliceSize
                }
            }
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
            removedCodeSignature: shouldRemoveCodeSignature && codeSignatureCommandIndex != nil,
            trimmedSliceSize: trimmedSliceSize
        )
    }

    /// 判断签名数据能否像 `codesign --remove-signature` 那样从文件中裁掉：
    /// 签名必须恰好位于 __LINKEDIT 末尾且位于切片末尾，否则只移除加载命令、保留数据。
    /// 返回裁剪后 __LINKEDIT 的 filesize 与切片的新大小（均相对切片起点）。
    private func codeSignatureTrim(for slice: MachOSlice, sliceSize: Int) -> (linkEditFileSize: UInt64, sliceSize: Int)? {
        guard sliceSize > 0,
              let signature = slice.codeSignature,
              let linkEdit = slice.segments.first(where: { $0.name == SEG_LINKEDIT })
        else {
            return nil
        }

        let signatureStart = UInt64(signature.dataOffset)
        let signatureEnd = signatureStart + UInt64(signature.dataSize)
        let (linkEditEnd, overflow) = linkEdit.fileOffset.addingReportingOverflow(linkEdit.fileSize)
        guard overflow == false,
              signature.dataSize > 0,
              signatureStart >= linkEdit.fileOffset,
              linkEditEnd == signatureEnd,
              signatureEnd == UInt64(sliceSize)
        else {
            return nil
        }

        return (signatureStart - linkEdit.fileOffset, Int(signatureStart))
    }

    /// 修改 __LINKEDIT 段命令的 filesize（vmsize 保持不变，与 codesign 的行为一致）。
    private func shrinkLinkEditSegment(_ commandData: Data, newFileSize: UInt64) -> Data {
        var data = commandData
        let command = data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: 0, as: UInt32.self)
        }
        if command == UInt32(LC_SEGMENT_64) {
            var segment = data.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: 0, as: segment_command_64.self)
            }
            segment.filesize = newFileSize
            writeStruct(segment, into: &data, at: 0)
        } else {
            var segment = data.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: 0, as: segment_command.self)
            }
            segment.filesize = UInt32(truncatingIfNeeded: newFileSize)
            writeStruct(segment, into: &data, at: 0)
        }
        return data
    }

    /// 把 fat 头中某个切片的 size 字段改为 `newSize`，按原文件的字节序写回。
    private func patchFatSliceSize(in data: inout Data, entry: FatArchitectureEntry, newSize: Int) {
        if entry.is64Bit {
            // fat_arch_64: cputype(4) cpusubtype(4) offset(8) size(8) align(4) reserved(4)
            let value = UInt64(newSize)
            writeStruct(entry.isByteSwapped ? value.byteSwapped : value, into: &data, at: entry.entryOffset + 16)
        } else {
            // fat_arch: cputype(4) cpusubtype(4) offset(4) size(4) align(4)
            let value = UInt32(truncatingIfNeeded: newSize)
            writeStruct(entry.isByteSwapped ? value.byteSwapped : value, into: &data, at: entry.entryOffset + 12)
        }
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

    private func ensureNativeByteOrder(_ slice: MachOSlice, in data: Data) throws {
        guard slice.offset >= 0, slice.offset + MemoryLayout<UInt32>.size <= data.count else {
            throw MachOWriteError.malformedLoadCommandArea(sliceOffset: slice.offset, reason: "the Mach-O header is out of bounds.")
        }
        let magic = data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: slice.offset, as: UInt32.self)
        }
        if magic == MH_CIGAM || magic == MH_CIGAM_64 {
            throw MachOWriteError.byteSwappedSliceUnsupported(sliceOffset: slice.offset)
        }
    }

    private func availableLoadCommandBytes(for slice: MachOSlice, fileSize: Int) throws -> Int {
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

        let available = payloadStart - headerSize
        let sizeofCommands = Int(slice.header.sizeofCommands)
        guard available >= 0 else {
            throw MachOWriteError.malformedLoadCommandArea(
                sliceOffset: slice.offset,
                reason: "the first section or segment (offset \(payloadStart)) starts inside the Mach-O header."
            )
        }
        guard sizeofCommands <= available else {
            throw MachOWriteError.malformedLoadCommandArea(
                sliceOffset: slice.offset,
                reason: "sizeofcmds (\(sizeofCommands)) overlaps file content that starts at offset \(payloadStart)."
            )
        }
        guard slice.offset + headerSize + available <= fileSize else {
            throw MachOWriteError.malformedLoadCommandArea(
                sliceOffset: slice.offset,
                reason: "the load command area extends past the end of the file."
            )
        }

        return available
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

    private func serializeDylibCommand(
        command: UInt32,
        path: String,
        timestamp: UInt32,
        currentVersion: MachOVersion,
        compatibilityVersion: MachOVersion,
        is64Bit: Bool
    ) throws -> Data {
        let alignment = is64Bit ? 8 : 4
        let pathData = utf8CStringData(path)
        let commandSize = alignedSize(MemoryLayout<dylib_command>.size + pathData.count, alignment: alignment)

        var dylibCommand = dylib_command()
        dylibCommand.cmd = command
        dylibCommand.cmdsize = UInt32(commandSize)
        dylibCommand.dylib.name.offset = UInt32(MemoryLayout<dylib_command>.size)
        dylibCommand.dylib.timestamp = timestamp
        dylibCommand.dylib.current_version = try packedVersion(currentVersion)
        dylibCommand.dylib.compatibility_version = try packedVersion(compatibilityVersion)

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

    private func serializeBuildVersionCommand(info: BuildVersionInfo, edit: PlatformEdit, is64Bit: Bool) throws -> Data {
        try serializeBuildVersionCommand(
            command: info.command,
            platform: edit.platform,
            minimumOS: edit.minimumOS,
            sdk: edit.sdk,
            tools: info.tools,
            is64Bit: is64Bit
        )
    }

    private func serializeBuildVersionCommand(edit: PlatformEdit, is64Bit: Bool) throws -> Data {
        try serializeBuildVersionCommand(
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
    ) throws -> Data {
        let alignment = is64Bit ? 8 : 4
        let totalSize = alignedSize(
            MemoryLayout<build_version_command>.size + tools.count * MemoryLayout<build_tool_version>.size,
            alignment: alignment
        )

        var buildVersionCommand = build_version_command()
        buildVersionCommand.cmd = command
        buildVersionCommand.cmdsize = UInt32(totalSize)
        buildVersionCommand.platform = rawValue(for: platform)
        buildVersionCommand.minos = try packedVersion(minimumOS)
        buildVersionCommand.sdk = try packedVersion(sdk)
        buildVersionCommand.ntools = UInt32(tools.count)

        var data = Data()
        appendStruct(buildVersionCommand, to: &data)
        for tool in tools {
            var toolVersion = build_tool_version()
            toolVersion.tool = tool.tool
            toolVersion.version = try packedVersion(tool.version)
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
        versionCommand.version = try packedVersion(edit.minimumOS)
        versionCommand.sdk = try packedVersion(edit.sdk)

        var data = Data()
        appendStruct(versionCommand, to: &data)
        if data.count < totalSize {
            data.append(Data(count: totalSize - data.count))
        }
        return data
    }

    private func usesBuildVersionCommand(for platform: MachOPlatform) -> Bool {
        switch platform {
        case .macOS, .iOS, .tvOS, .watchOS:
            return false
        default:
            return true
        }
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

    private func packedVersion(_ version: MachOVersion) throws -> UInt32 {
        do {
            return try version.packedValue()
        } catch {
            throw MachOWriteError.invalidVersion(version)
        }
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
    /// 签名数据被裁掉后切片的新大小；nil 表示没有裁剪。
    let trimmedSliceSize: Int?
}

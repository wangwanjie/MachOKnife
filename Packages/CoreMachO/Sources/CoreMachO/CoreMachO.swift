import CoreMachOC
import Foundation

public enum MachOParseError: Error {
    case fileTooSmall
    case unsupportedMagic(UInt32)
    case outOfBounds(offset: Int, size: Int)
    case invalidLoadCommandSize(UInt32)
}

struct MachOFileParser {
    let data: Data

    init(data: Data) {
        // 解析代码统一按 0 起始的下标访问 Data；传入切片（startIndex != 0）时先复制一份，
        // 避免 `data[a..<b]` 这类绝对下标访问与 `withUnsafeBytes` 的相对偏移不一致。
        if data.startIndex == 0 {
            self.data = data
        } else {
            self.data = Data(data)
        }
    }

    func parseContainer() throws -> MachOContainer {
        let magic = try read(UInt32.self, at: 0)

        switch magic {
        case FAT_MAGIC, FAT_CIGAM, FAT_MAGIC_64, FAT_CIGAM_64:
            let slices = try fatArchitectureEntries().map { entry in
                try parseSlice(at: entry.offset, magic: try thinSliceMagic(at: entry.offset))
            }
            return MachOContainer(kind: .fat, slices: slices)
        case MH_MAGIC, MH_CIGAM, MH_MAGIC_64, MH_CIGAM_64:
            return MachOContainer(kind: .thin, slices: [try parseSlice(at: 0, magic: magic)])
        default:
            throw MachOParseError.unsupportedMagic(magic)
        }
    }

    func parseMetadataScan(fileURL: URL, fileSize: Int) throws -> MachOMetadataScan {
        let magic = try read(UInt32.self, at: 0)

        switch magic {
        case FAT_MAGIC, FAT_CIGAM, FAT_MAGIC_64, FAT_CIGAM_64:
            let slices = try fatArchitectureEntries().map { entry in
                try scanSlice(at: entry.offset, magic: try thinSliceMagic(at: entry.offset))
            }
            return MachOMetadataScan(
                fileURL: fileURL,
                fileSize: fileSize,
                kind: .fat,
                slices: slices
            )
        case MH_MAGIC, MH_CIGAM, MH_MAGIC_64, MH_CIGAM_64:
            return MachOMetadataScan(
                fileURL: fileURL,
                fileSize: fileSize,
                kind: .thin,
                slices: [try scanSlice(at: 0, magic: magic)]
            )
        default:
            throw MachOParseError.unsupportedMagic(magic)
        }
    }

    /// 只读取每个切片的 Mach-O 头部（CPU 类型/子类型），不解析加载命令和符号表。
    /// 用于静态库成员等只需要识别架构的场景，避免对每个成员做完整解析。
    func sliceCPUTypes() throws -> [(cpuType: Int32, cpuSubtype: Int32)] {
        let magic = try read(UInt32.self, at: 0)

        switch magic {
        case FAT_MAGIC, FAT_CIGAM, FAT_MAGIC_64, FAT_CIGAM_64:
            return try fatArchitectureEntries().map { entry in
                let header = try parseHeader(at: entry.offset, magic: try thinSliceMagic(at: entry.offset))
                return (header.info.cpuType, header.info.cpuSubtype)
            }
        case MH_MAGIC, MH_CIGAM, MH_MAGIC_64, MH_CIGAM_64:
            let header = try parseHeader(at: 0, magic: magic)
            return [(header.info.cpuType, header.info.cpuSubtype)]
        default:
            throw MachOParseError.unsupportedMagic(magic)
        }
    }

    /// 解析 fat 头中的全部 `fat_arch` / `fat_arch_64` 条目。
    /// 调用方需保证文件以 fat magic 开头；`nfat_arch` 与切片偏移都来自不可信输入，这里统一做边界校验。
    func fatArchitectureEntries() throws -> [FatArchitectureEntry] {
        let magic = try read(UInt32.self, at: 0)
        let swapped = magic == FAT_CIGAM || magic == FAT_CIGAM_64
        let is64Bit = magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64
        let header = try read(fat_header.self, at: 0)
        let architectureCount = Int(normalize(header.nfat_arch, swapped: swapped))
        let entrySize = is64Bit ? MemoryLayout<fat_arch_64>.size : MemoryLayout<fat_arch>.size
        let entriesStart = MemoryLayout<fat_header>.size

        // 先确认所有条目都位于文件内，避免 nfat_arch 被篡改成超大值时按其数量预分配数组导致内存耗尽。
        guard architectureCount <= (data.count - entriesStart) / entrySize else {
            throw MachOParseError.outOfBounds(offset: entriesStart, size: architectureCount * entrySize)
        }

        var entries = [FatArchitectureEntry]()
        entries.reserveCapacity(architectureCount)
        for index in 0..<architectureCount {
            let entryOffset = entriesStart + index * entrySize
            if is64Bit {
                let architecture = try read(fat_arch_64.self, at: entryOffset)
                entries.append(
                    FatArchitectureEntry(
                        entryOffset: entryOffset,
                        is64Bit: true,
                        isByteSwapped: swapped,
                        cpuType: normalize(architecture.cputype, swapped: swapped),
                        cpuSubtype: normalize(architecture.cpusubtype, swapped: swapped),
                        offset: try fatSliceOffset(normalize(architecture.offset, swapped: swapped)),
                        size: normalize(architecture.size, swapped: swapped)
                    )
                )
            } else {
                let architecture = try read(fat_arch.self, at: entryOffset)
                entries.append(
                    FatArchitectureEntry(
                        entryOffset: entryOffset,
                        is64Bit: false,
                        isByteSwapped: swapped,
                        cpuType: normalize(architecture.cputype, swapped: swapped),
                        cpuSubtype: normalize(architecture.cpusubtype, swapped: swapped),
                        offset: try fatSliceOffset(UInt64(normalize(architecture.offset, swapped: swapped))),
                        size: UInt64(normalize(architecture.size, swapped: swapped))
                    )
                )
            }
        }
        return entries
    }

    /// Converts a fat slice offset to `Int`, throwing instead of trapping when the
    /// recorded value does not fit or lies beyond the end of the file.
    private func fatSliceOffset(_ rawOffset: UInt64) throws -> Int {
        guard let offset = Int(exactly: rawOffset), offset <= data.count else {
            throw MachOParseError.outOfBounds(offset: Int(clamping: rawOffset), size: MemoryLayout<UInt32>.size)
        }
        return offset
    }

    /// 读取 fat 切片的 magic，并要求它是 thin Mach-O。
    /// 以前任何 magic 都会被当成 32 位小端头解析，fat 静态库切片或损坏文件会产出垃圾结果。
    private func thinSliceMagic(at offset: Int) throws -> UInt32 {
        let magic = try read(UInt32.self, at: offset)
        switch magic {
        case MH_MAGIC, MH_CIGAM, MH_MAGIC_64, MH_CIGAM_64:
            return magic
        default:
            throw MachOParseError.unsupportedMagic(magic)
        }
    }

    private func parseSlice(at offset: Int, magic: UInt32) throws -> MachOSlice {
        let components = try parseSliceComponents(at: offset, magic: magic)

        let symbols = try components.symbolTable.map {
            try parseSymbols(
                using: $0,
                sliceOffset: offset,
                is64Bit: components.header.is64Bit,
                swapped: components.swapped
            )
        } ?? []

        return MachOSlice(
            offset: offset,
            header: components.header,
            loadCommands: components.loadCommands,
            installNameInfo: components.installNameInfo,
            dylibReferences: components.dylibReferences,
            rpathCommands: components.rpathCommands,
            buildVersion: components.buildVersion,
            versionMin: components.versionMin,
            segments: components.segments,
            symbolTable: components.symbolTable,
            symbols: symbols,
            uuid: components.uuid,
            codeSignature: components.codeSignature,
            encryptionInfo: components.encryptionInfo
        )
    }

    private func scanSlice(at offset: Int, magic: UInt32) throws -> MachOMetadataSlice {
        let components = try parseSliceComponents(at: offset, magic: magic)

        return MachOMetadataSlice(
            offset: offset,
            header: components.header,
            loadCommands: components.loadCommands,
            installNameInfo: components.installNameInfo,
            dylibReferences: components.dylibReferences,
            rpathCommands: components.rpathCommands,
            buildVersion: components.buildVersion,
            versionMin: components.versionMin,
            segments: components.segments,
            symbolTable: components.symbolTable,
            uuid: components.uuid,
            codeSignature: components.codeSignature,
            encryptionInfo: components.encryptionInfo,
            heavyCollectionEstimate: makeHeavyCollectionEstimate(from: components),
            isByteSwapped: components.swapped
        )
    }

    private func parseSliceComponents(at offset: Int, magic: UInt32) throws -> ParsedSliceComponents {
        let parsedHeader = try parseHeader(at: offset, magic: magic)
        let commandsStart = offset + parsedHeader.headerSize
        let commandsEnd = commandsStart + Int(parsedHeader.info.sizeofCommands)
        guard commandsEnd <= data.count else {
            throw MachOParseError.outOfBounds(offset: commandsStart, size: Int(parsedHeader.info.sizeofCommands))
        }

        var cursor = commandsStart
        var loadCommands = [MachOLoadCommandInfo]()
        // ncmds 来自不可信文件：每条加载命令至少 8 字节，预分配数量不超过 sizeofcmds 能容纳的上限，
        // 防止 ncmds 被篡改为超大值时一次性申请巨量内存。
        let maximumCommandCount = Int(parsedHeader.info.sizeofCommands) / MemoryLayout<load_command>.size
        loadCommands.reserveCapacity(min(Int(parsedHeader.info.numberOfCommands), maximumCommandCount))
        var installNameInfo: DylibCommandInfo?
        var dylibReferences = [DylibCommandInfo]()
        var rpathCommands = [RPathCommandInfo]()
        var buildVersion: BuildVersionInfo?
        var versionMin: VersionMinInfo?
        var segments = [SegmentInfo]()
        var symbolTable: SymbolTableInfo?
        var uuid: UUID?
        var codeSignature: LinkEditDataInfo?
        var encryptionInfo: EncryptionInfo?

        for _ in 0..<parsedHeader.info.numberOfCommands {
            guard cursor + MemoryLayout<load_command>.size <= commandsEnd else {
                throw MachOParseError.outOfBounds(offset: cursor, size: MemoryLayout<load_command>.size)
            }

            let command = try read(load_command.self, at: cursor)
            let commandType = normalize(command.cmd, swapped: parsedHeader.swapped)
            let commandSize = normalize(command.cmdsize, swapped: parsedHeader.swapped)

            guard commandSize >= UInt32(MemoryLayout<load_command>.size) else {
                throw MachOParseError.invalidLoadCommandSize(commandSize)
            }

            let commandEnd = cursor + Int(commandSize)
            guard commandEnd <= commandsEnd else {
                throw MachOParseError.outOfBounds(offset: cursor, size: Int(commandSize))
            }

            let payload = try parseLoadCommandPayload(
                commandType: commandType,
                commandSize: commandSize,
                commandOffset: cursor,
                swapped: parsedHeader.swapped
            )

            if case let .dylib(info)? = payload {
                if commandType == UInt32(LC_ID_DYLIB) {
                    installNameInfo = info
                } else {
                    dylibReferences.append(info)
                }
            } else if case let .rpath(info)? = payload {
                rpathCommands.append(info)
            } else if case let .buildVersion(info)? = payload {
                buildVersion = info
            } else if case let .versionMin(info)? = payload {
                versionMin = info
            } else if case let .segment(info)? = payload {
                segments.append(info)
            } else if case let .symbolTable(info)? = payload {
                symbolTable = info
            } else if case let .uuid(info)? = payload {
                uuid = info
            } else if case let .codeSignature(info)? = payload {
                codeSignature = info
            } else if case let .encryptionInfo(info)? = payload {
                encryptionInfo = info
            }

            loadCommands.append(
                MachOLoadCommandInfo(
                    command: commandType,
                    size: commandSize,
                    offset: cursor,
                    payload: payload
                )
            )

            cursor = commandEnd
        }

        return ParsedSliceComponents(
            header: parsedHeader.info,
            loadCommands: loadCommands,
            installNameInfo: installNameInfo,
            dylibReferences: dylibReferences,
            rpathCommands: rpathCommands,
            buildVersion: buildVersion,
            versionMin: versionMin,
            segments: segments,
            symbolTable: symbolTable,
            uuid: uuid,
            codeSignature: codeSignature,
            encryptionInfo: encryptionInfo,
            swapped: parsedHeader.swapped
        )
    }

    private func makeHeavyCollectionEstimate(from components: ParsedSliceComponents) -> MachOHeavyCollectionEstimate {
        let sectionCount = components.segments.reduce(0) { $0 + $1.sections.count }
        let symbolCount = Int(components.symbolTable?.symbolCount ?? 0)
        let stringTableSize = Int(components.symbolTable?.stringTableSize ?? 0)
        let estimatedNodeCount =
            components.loadCommands.count
            + components.dylibReferences.count
            + components.rpathCommands.count
            + components.segments.count
            + sectionCount
            + symbolCount
            + 10

        return MachOHeavyCollectionEstimate(
            symbolCount: symbolCount,
            stringTableSize: stringTableSize,
            estimatedNodeCount: estimatedNodeCount
        )
    }

    private func parseLoadCommandPayload(
        commandType: UInt32,
        commandSize: UInt32,
        commandOffset: Int,
        swapped: Bool
    ) throws -> MachOLoadCommandInfo.Payload? {
        // 已知命令的 cmdsize 必须能容纳其固定结构体，否则读取的字段会越过本命令、落到后续命令或文件内容上。
        if let minimumSize = minimumCommandSize(for: commandType), Int(commandSize) < minimumSize {
            throw MachOParseError.invalidLoadCommandSize(commandSize)
        }

        switch commandType {
        case UInt32(LC_ID_DYLIB), UInt32(LC_LOAD_DYLIB), UInt32(LC_LOAD_WEAK_DYLIB), UInt32(LC_REEXPORT_DYLIB), UInt32(LC_LOAD_UPWARD_DYLIB):
            return .dylib(try parseDylibCommand(at: commandOffset, swapped: swapped))
        case UInt32(LC_RPATH):
            return .rpath(try parseRPathCommand(at: commandOffset, swapped: swapped))
        case UInt32(LC_BUILD_VERSION):
            return .buildVersion(try parseBuildVersionCommand(at: commandOffset, commandSize: commandSize, swapped: swapped))
        case UInt32(LC_VERSION_MIN_MACOSX), UInt32(LC_VERSION_MIN_IPHONEOS), UInt32(LC_VERSION_MIN_TVOS), UInt32(LC_VERSION_MIN_WATCHOS):
            return .versionMin(try parseVersionMinCommand(at: commandOffset, command: commandType, swapped: swapped))
        case UInt32(LC_SEGMENT):
            return .segment(try parseSegmentCommand32(at: commandOffset, command: commandType, commandSize: commandSize, swapped: swapped))
        case UInt32(LC_SEGMENT_64):
            return .segment(try parseSegmentCommand64(at: commandOffset, command: commandType, commandSize: commandSize, swapped: swapped))
        case UInt32(LC_SYMTAB):
            return .symbolTable(try parseSymbolTableCommand(at: commandOffset, command: commandType, swapped: swapped))
        case UInt32(LC_UUID):
            return .uuid(try parseUUIDCommand(at: commandOffset))
        case UInt32(LC_CODE_SIGNATURE):
            return .codeSignature(try parseLinkEditDataCommand(at: commandOffset, command: commandType, swapped: swapped))
        case UInt32(LC_ENCRYPTION_INFO):
            return .encryptionInfo(try parseEncryptionInfo32(at: commandOffset, command: commandType, swapped: swapped))
        case UInt32(LC_ENCRYPTION_INFO_64):
            return .encryptionInfo(try parseEncryptionInfo64(at: commandOffset, command: commandType, swapped: swapped))
        default:
            return nil
        }
    }

    /// 返回会被解析出 payload 的加载命令所需的最小 cmdsize；未知命令返回 nil。
    private func minimumCommandSize(for commandType: UInt32) -> Int? {
        switch commandType {
        case UInt32(LC_ID_DYLIB), UInt32(LC_LOAD_DYLIB), UInt32(LC_LOAD_WEAK_DYLIB), UInt32(LC_REEXPORT_DYLIB), UInt32(LC_LOAD_UPWARD_DYLIB):
            return MemoryLayout<dylib_command>.size
        case UInt32(LC_RPATH):
            return MemoryLayout<rpath_command>.size
        case UInt32(LC_BUILD_VERSION):
            return MemoryLayout<build_version_command>.size
        case UInt32(LC_VERSION_MIN_MACOSX), UInt32(LC_VERSION_MIN_IPHONEOS), UInt32(LC_VERSION_MIN_TVOS), UInt32(LC_VERSION_MIN_WATCHOS):
            return MemoryLayout<version_min_command>.size
        case UInt32(LC_SEGMENT):
            return MemoryLayout<segment_command>.size
        case UInt32(LC_SEGMENT_64):
            return MemoryLayout<segment_command_64>.size
        case UInt32(LC_SYMTAB):
            return MemoryLayout<symtab_command>.size
        case UInt32(LC_UUID):
            return MemoryLayout<uuid_command>.size
        case UInt32(LC_CODE_SIGNATURE):
            return MemoryLayout<linkedit_data_command>.size
        case UInt32(LC_ENCRYPTION_INFO):
            return MemoryLayout<encryption_info_command>.size
        case UInt32(LC_ENCRYPTION_INFO_64):
            return MemoryLayout<encryption_info_command_64>.size
        default:
            return nil
        }
    }

    private func parseDylibCommand(at offset: Int, swapped: Bool) throws -> DylibCommandInfo {
        let command = try read(dylib_command.self, at: offset)
        let commandType = normalize(command.cmd, swapped: swapped)
        let nameOffset = normalize(command.dylib.name.offset, swapped: swapped)
        let path = try readLoadCommandString(at: offset, stringOffset: nameOffset, commandSize: normalize(command.cmdsize, swapped: swapped))

        return DylibCommandInfo(
            command: commandType,
            path: path,
            commandOffset: offset,
            nameOffset: nameOffset,
            timestamp: normalize(command.dylib.timestamp, swapped: swapped),
            currentVersion: parseVersion(normalize(command.dylib.current_version, swapped: swapped)),
            compatibilityVersion: parseVersion(normalize(command.dylib.compatibility_version, swapped: swapped))
        )
    }

    private func parseRPathCommand(at offset: Int, swapped: Bool) throws -> RPathCommandInfo {
        let command = try read(rpath_command.self, at: offset)
        let pathOffset = normalize(command.path.offset, swapped: swapped)
        let path = try readLoadCommandString(at: offset, stringOffset: pathOffset, commandSize: normalize(command.cmdsize, swapped: swapped))

        return RPathCommandInfo(
            command: normalize(command.cmd, swapped: swapped),
            path: path,
            commandOffset: offset,
            pathOffset: pathOffset
        )
    }

    private func parseBuildVersionCommand(at offset: Int, commandSize: UInt32, swapped: Bool) throws -> BuildVersionInfo {
        let command = try read(build_version_command.self, at: offset)
        let toolCount = Int(normalize(command.ntools, swapped: swapped))
        let toolsStart = offset + MemoryLayout<build_version_command>.size
        // ntools 不可信：工具条目必须全部落在本命令 cmdsize 范围内。
        // 以前既不校验也会按 ntools 预分配，篡改后的 ntools 会读到后续命令甚至耗尽内存。
        let maximumToolCount = (Int(commandSize) - MemoryLayout<build_version_command>.size) / MemoryLayout<build_tool_version>.size
        guard toolCount <= maximumToolCount else {
            throw MachOParseError.invalidLoadCommandSize(commandSize)
        }
        var tools = [BuildToolVersionInfo]()
        tools.reserveCapacity(toolCount)

        for index in 0..<toolCount {
            let toolOffset = toolsStart + index * MemoryLayout<build_tool_version>.size
            let tool = try read(build_tool_version.self, at: toolOffset)
            tools.append(
                BuildToolVersionInfo(
                    tool: normalize(tool.tool, swapped: swapped),
                    version: parseVersion(normalize(tool.version, swapped: swapped))
                )
            )
        }

        return BuildVersionInfo(
            command: normalize(command.cmd, swapped: swapped),
            commandOffset: offset,
            platform: MachOPlatform(rawValue: normalize(command.platform, swapped: swapped)),
            minimumOS: parseVersion(normalize(command.minos, swapped: swapped)),
            sdk: parseVersion(normalize(command.sdk, swapped: swapped)),
            tools: tools
        )
    }

    private func parseVersionMinCommand(at offset: Int, command: UInt32, swapped: Bool) throws -> VersionMinInfo {
        let versionCommand = try read(version_min_command.self, at: offset)
        return VersionMinInfo(
            command: command,
            commandOffset: offset,
            platform: platform(forVersionMinCommand: command),
            minimumOS: parseVersion(normalize(versionCommand.version, swapped: swapped)),
            sdk: parseVersion(normalize(versionCommand.sdk, swapped: swapped))
        )
    }

    private func parseSegmentCommand32(at offset: Int, command: UInt32, commandSize: UInt32, swapped: Bool) throws -> SegmentInfo {
        let segment = try read(segment_command.self, at: offset)
        let sectionCount = Int(normalize(segment.nsects, swapped: swapped))
        let sectionsStart = offset + MemoryLayout<segment_command>.size
        let minimumSize = MemoryLayout<segment_command>.size + sectionCount * MemoryLayout<section>.size
        guard Int(commandSize) >= minimumSize else {
            throw MachOParseError.invalidLoadCommandSize(commandSize)
        }

        let sections = try (0..<sectionCount).map { index in
            let sectionOffset = sectionsStart + index * MemoryLayout<section>.size
            let sectionInfo = try read(section.self, at: sectionOffset)
            return SectionInfo(
                name: fixedWidthString(from: sectionInfo.sectname),
                segmentName: fixedWidthString(from: sectionInfo.segname),
                address: UInt64(normalize(sectionInfo.addr, swapped: swapped)),
                size: UInt64(normalize(sectionInfo.size, swapped: swapped)),
                fileOffset: normalize(sectionInfo.offset, swapped: swapped),
                alignment: normalize(sectionInfo.align, swapped: swapped),
                relocationOffset: normalize(sectionInfo.reloff, swapped: swapped),
                relocationCount: normalize(sectionInfo.nreloc, swapped: swapped),
                flags: normalize(sectionInfo.flags, swapped: swapped)
            )
        }

        return SegmentInfo(
            command: command,
            commandOffset: offset,
            name: fixedWidthString(from: segment.segname),
            vmAddress: UInt64(normalize(segment.vmaddr, swapped: swapped)),
            vmSize: UInt64(normalize(segment.vmsize, swapped: swapped)),
            fileOffset: UInt64(normalize(segment.fileoff, swapped: swapped)),
            fileSize: UInt64(normalize(segment.filesize, swapped: swapped)),
            maxProtection: SegmentProtection(rawValue: normalize(segment.maxprot, swapped: swapped)),
            initialProtection: SegmentProtection(rawValue: normalize(segment.initprot, swapped: swapped)),
            flags: normalize(segment.flags, swapped: swapped),
            sections: sections
        )
    }

    private func parseSegmentCommand64(at offset: Int, command: UInt32, commandSize: UInt32, swapped: Bool) throws -> SegmentInfo {
        let segment = try read(segment_command_64.self, at: offset)
        let sectionCount = Int(normalize(segment.nsects, swapped: swapped))
        let sectionsStart = offset + MemoryLayout<segment_command_64>.size
        let minimumSize = MemoryLayout<segment_command_64>.size + sectionCount * MemoryLayout<section_64>.size
        guard Int(commandSize) >= minimumSize else {
            throw MachOParseError.invalidLoadCommandSize(commandSize)
        }

        let sections = try (0..<sectionCount).map { index in
            let sectionOffset = sectionsStart + index * MemoryLayout<section_64>.size
            let sectionInfo = try read(section_64.self, at: sectionOffset)
            return SectionInfo(
                name: fixedWidthString(from: sectionInfo.sectname),
                segmentName: fixedWidthString(from: sectionInfo.segname),
                address: normalize(sectionInfo.addr, swapped: swapped),
                size: normalize(sectionInfo.size, swapped: swapped),
                fileOffset: normalize(sectionInfo.offset, swapped: swapped),
                alignment: normalize(sectionInfo.align, swapped: swapped),
                relocationOffset: normalize(sectionInfo.reloff, swapped: swapped),
                relocationCount: normalize(sectionInfo.nreloc, swapped: swapped),
                flags: normalize(sectionInfo.flags, swapped: swapped)
            )
        }

        return SegmentInfo(
            command: command,
            commandOffset: offset,
            name: fixedWidthString(from: segment.segname),
            vmAddress: normalize(segment.vmaddr, swapped: swapped),
            vmSize: normalize(segment.vmsize, swapped: swapped),
            fileOffset: normalize(segment.fileoff, swapped: swapped),
            fileSize: normalize(segment.filesize, swapped: swapped),
            maxProtection: SegmentProtection(rawValue: normalize(segment.maxprot, swapped: swapped)),
            initialProtection: SegmentProtection(rawValue: normalize(segment.initprot, swapped: swapped)),
            flags: normalize(segment.flags, swapped: swapped),
            sections: sections
        )
    }

    private func parseSymbolTableCommand(at offset: Int, command: UInt32, swapped: Bool) throws -> SymbolTableInfo {
        let symbolTableCommand = try read(symtab_command.self, at: offset)
        return SymbolTableInfo(
            command: command,
            commandOffset: offset,
            symbolOffset: normalize(symbolTableCommand.symoff, swapped: swapped),
            symbolCount: normalize(symbolTableCommand.nsyms, swapped: swapped),
            stringTableOffset: normalize(symbolTableCommand.stroff, swapped: swapped),
            stringTableSize: normalize(symbolTableCommand.strsize, swapped: swapped)
        )
    }

    private func parseUUIDCommand(at offset: Int) throws -> UUID {
        let command = try read(uuid_command.self, at: offset)
        let bytes = withUnsafeBytes(of: command.uuid) { Array($0) }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func parseLinkEditDataCommand(at offset: Int, command: UInt32, swapped: Bool) throws -> LinkEditDataInfo {
        let dataCommand = try read(linkedit_data_command.self, at: offset)
        return LinkEditDataInfo(
            command: command,
            commandOffset: offset,
            dataOffset: normalize(dataCommand.dataoff, swapped: swapped),
            dataSize: normalize(dataCommand.datasize, swapped: swapped)
        )
    }

    private func parseEncryptionInfo32(at offset: Int, command: UInt32, swapped: Bool) throws -> EncryptionInfo {
        let encryptionCommand = try read(encryption_info_command.self, at: offset)
        return EncryptionInfo(
            command: command,
            commandOffset: offset,
            cryptOffset: normalize(encryptionCommand.cryptoff, swapped: swapped),
            cryptSize: normalize(encryptionCommand.cryptsize, swapped: swapped),
            cryptID: normalize(encryptionCommand.cryptid, swapped: swapped)
        )
    }

    private func parseEncryptionInfo64(at offset: Int, command: UInt32, swapped: Bool) throws -> EncryptionInfo {
        let encryptionCommand = try read(encryption_info_command_64.self, at: offset)
        return EncryptionInfo(
            command: command,
            commandOffset: offset,
            cryptOffset: normalize(encryptionCommand.cryptoff, swapped: swapped),
            cryptSize: normalize(encryptionCommand.cryptsize, swapped: swapped),
            cryptID: normalize(encryptionCommand.cryptid, swapped: swapped)
        )
    }

    func readSymbolPage(
        slice: MachOMetadataSlice,
        startIndex: Int,
        maximumCount: Int
    ) throws -> MachOSymbolTablePage {
        guard maximumCount > 0 else {
            throw MachOSymbolTableReaderError.invalidMaximumCount(maximumCount)
        }
        guard let symbolTable = slice.symbolTable else {
            throw MachOSymbolTableReaderError.missingSymbolTable
        }

        let totalSymbolCount = Int(symbolTable.symbolCount)
        guard startIndex >= 0, startIndex < totalSymbolCount else {
            throw MachOSymbolTableReaderError.startIndexOutOfBounds(
                startIndex: startIndex,
                totalSymbolCount: totalSymbolCount
            )
        }

        // 用剩余数量做比较而不是 startIndex + maximumCount，避免 maximumCount 很大（如 Int.max）时整数溢出崩溃。
        let endIndex = startIndex + min(maximumCount, totalSymbolCount - startIndex)
        let symbols = try parseSymbols(
            using: symbolTable,
            sliceOffset: slice.offset,
            is64Bit: slice.header.is64Bit,
            swapped: slice.isByteSwapped,
            range: startIndex..<endIndex
        )

        return MachOSymbolTablePage(
            startIndex: startIndex,
            symbols: symbols,
            totalSymbolCount: totalSymbolCount
        )
    }

    func readStringTableBatch(
        slice: MachOMetadataSlice,
        startIndex: Int,
        maximumCount: Int
    ) throws -> MachOStringTableBatch {
        guard maximumCount > 0 else {
            throw MachOStringTableReaderError.invalidMaximumCount(maximumCount)
        }
        guard let symbolTable = slice.symbolTable else {
            throw MachOStringTableReaderError.missingSymbolTable
        }

        let stringTableStart = slice.offset + Int(symbolTable.stringTableOffset)
        let stringTableSize = Int(symbolTable.stringTableSize)
        let stringTableEnd = stringTableStart + stringTableSize
        guard stringTableStart >= 0, stringTableEnd <= data.count else {
            throw MachOParseError.outOfBounds(offset: stringTableStart, size: stringTableSize)
        }

        guard startIndex >= 0 else {
            throw MachOStringTableReaderError.startIndexOutOfBounds(
                startIndex: startIndex,
                totalEntryCount: 0
            )
        }

        var entries = [MachOStringTableEntry]()
        // 预分配不超过字符串表字节数（每条至少 1 字节），避免调用方传入超大 maximumCount 时申请巨量内存。
        entries.reserveCapacity(min(maximumCount, stringTableSize))

        var totalEntryCount = 0
        var cursor = stringTableStart
        while cursor < stringTableEnd {
            let entryOffset = cursor - stringTableStart
            // 按原始字节查找 NUL 结尾：以前用解码后字符串的 utf8.count 推进游标，
            // 非法 UTF-8 字节会被替换为 3 字节的 U+FFFD，导致游标错位、后续条目全部解析错误。
            let terminator = data[cursor..<stringTableEnd].firstIndex(of: 0) ?? stringTableEnd
            if totalEntryCount >= startIndex, entries.count < maximumCount {
                let string = String(decoding: data[cursor..<terminator], as: UTF8.self)
                entries.append(MachOStringTableEntry(stringTableIndex: entryOffset, string: string))
            }
            totalEntryCount += 1
            cursor = terminator + 1
        }

        guard startIndex < totalEntryCount else {
            throw MachOStringTableReaderError.startIndexOutOfBounds(
                startIndex: startIndex,
                totalEntryCount: totalEntryCount
            )
        }

        return MachOStringTableBatch(
            startIndex: startIndex,
            entries: entries,
            totalEntryCount: totalEntryCount,
            totalStringTableSize: stringTableSize
        )
    }

    private func parseSymbols(
        using symbolTable: SymbolTableInfo,
        sliceOffset: Int,
        is64Bit: Bool,
        swapped: Bool,
        range: Range<Int>? = nil
    ) throws -> [SymbolInfo] {
        let count = Int(symbolTable.symbolCount)
        let symbolRange = range ?? 0..<count
        guard symbolRange.lowerBound >= 0, symbolRange.upperBound <= count else {
            throw MachOParseError.outOfBounds(offset: symbolRange.lowerBound, size: symbolRange.count)
        }
        let symbolEntrySize = is64Bit ? MemoryLayout<nlist_64>.size : MemoryLayout<nlist>.size
        let symbolsStart = sliceOffset + Int(symbolTable.symbolOffset)
        let symbolsSize = count * symbolEntrySize
        guard symbolsStart >= 0, symbolsStart + symbolsSize <= data.count else {
            throw MachOParseError.outOfBounds(offset: symbolsStart, size: symbolsSize)
        }

        let stringTableStart = sliceOffset + Int(symbolTable.stringTableOffset)
        let stringTableSize = Int(symbolTable.stringTableSize)
        guard stringTableStart >= 0, stringTableStart + stringTableSize <= data.count else {
            throw MachOParseError.outOfBounds(offset: stringTableStart, size: stringTableSize)
        }

        return try symbolRange.map { index in
            let offset = symbolsStart + index * symbolEntrySize
            if is64Bit {
                let symbol = try read(nlist_64.self, at: offset)
                let stringTableIndex = normalize(symbol.n_un.n_strx, swapped: swapped)
                return SymbolInfo(
                    name: try readStringTableEntry(
                        at: stringTableStart,
                        size: stringTableSize,
                        index: stringTableIndex
                    ),
                    stringTableIndex: stringTableIndex,
                    type: symbol.n_type,
                    sectionNumber: symbol.n_sect,
                    description: normalizeSymbolDescription(symbol.n_desc, swapped: swapped),
                    value: normalize(symbol.n_value, swapped: swapped)
                )
            } else {
                let symbol = try read(nlist.self, at: offset)
                let stringTableIndex = normalize(symbol.n_un.n_strx, swapped: swapped)
                return SymbolInfo(
                    name: try readStringTableEntry(
                        at: stringTableStart,
                        size: stringTableSize,
                        index: stringTableIndex
                    ),
                    stringTableIndex: stringTableIndex,
                    type: symbol.n_type,
                    sectionNumber: symbol.n_sect,
                    description: normalizeSymbolDescription(symbol.n_desc, swapped: swapped),
                    value: UInt64(normalize(symbol.n_value, swapped: swapped))
                )
            }
        }
    }

    private func parseHeader(at offset: Int, magic: UInt32) throws -> ParsedHeader {
        let swapped = magic == MH_CIGAM || magic == MH_CIGAM_64
        let is64Bit = magic == MH_MAGIC_64 || magic == MH_CIGAM_64

        if is64Bit {
            let header = try read(mach_header_64.self, at: offset)
            return ParsedHeader(
                info: MachOHeaderInfo(
                    is64Bit: true,
                    cpuType: normalize(header.cputype, swapped: swapped),
                    cpuSubtype: normalize(header.cpusubtype, swapped: swapped),
                    fileType: normalize(header.filetype, swapped: swapped),
                    numberOfCommands: normalize(header.ncmds, swapped: swapped),
                    sizeofCommands: normalize(header.sizeofcmds, swapped: swapped),
                    flags: normalize(header.flags, swapped: swapped),
                    reserved: normalize(header.reserved, swapped: swapped)
                ),
                swapped: swapped,
                headerSize: MemoryLayout<mach_header_64>.size
            )
        } else {
            let header = try read(mach_header.self, at: offset)
            return ParsedHeader(
                info: MachOHeaderInfo(
                    is64Bit: false,
                    cpuType: normalize(header.cputype, swapped: swapped),
                    cpuSubtype: normalize(header.cpusubtype, swapped: swapped),
                    fileType: normalize(header.filetype, swapped: swapped),
                    numberOfCommands: normalize(header.ncmds, swapped: swapped),
                    sizeofCommands: normalize(header.sizeofcmds, swapped: swapped),
                    flags: normalize(header.flags, swapped: swapped),
                    reserved: nil
                ),
                swapped: swapped,
                headerSize: MemoryLayout<mach_header>.size
            )
        }
    }

    private func read<T>(_ type: T.Type, at offset: Int) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset >= 0, offset + size <= data.count else {
            throw MachOParseError.outOfBounds(offset: offset, size: size)
        }

        return data.withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(fromByteOffset: offset, as: T.self)
        }
    }

    private func readLoadCommandString(at commandOffset: Int, stringOffset: UInt32, commandSize: UInt32) throws -> String {
        let stringStart = commandOffset + Int(stringOffset)
        let commandEnd = commandOffset + Int(commandSize)
        guard stringStart < commandEnd, commandEnd <= data.count else {
            throw MachOParseError.outOfBounds(offset: stringStart, size: max(0, commandEnd - stringStart))
        }

        let bytes = data[stringStart..<commandEnd]
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    private func readStringTableEntry(at stringTableOffset: Int, size: Int, index: UInt32) throws -> String {
        if index == 0 {
            return ""
        }

        let start = stringTableOffset + Int(index)
        let end = stringTableOffset + size
        guard start >= stringTableOffset, start < end, end <= data.count else {
            throw MachOParseError.outOfBounds(offset: start, size: max(0, end - start))
        }

        return String(decoding: data[start..<end].prefix { $0 != 0 }, as: UTF8.self)
    }

    private func parseVersion(_ rawValue: UInt32) -> MachOVersion {
        MachOVersion(
            major: Int((rawValue >> 16) & 0xffff),
            minor: Int((rawValue >> 8) & 0xff),
            patch: Int(rawValue & 0xff)
        )
    }

    private func fixedWidthString<T>(from value: T) -> String {
        withUnsafeBytes(of: value) { rawBuffer in
            String(decoding: rawBuffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private func platform(forVersionMinCommand command: UInt32) -> MachOPlatform {
        switch command {
        case UInt32(LC_VERSION_MIN_MACOSX):
            return .macOS
        case UInt32(LC_VERSION_MIN_IPHONEOS):
            return .iOS
        case UInt32(LC_VERSION_MIN_TVOS):
            return .tvOS
        case UInt32(LC_VERSION_MIN_WATCHOS):
            return .watchOS
        default:
            return .unknown(command)
        }
    }

    private func normalize(_ value: UInt32, swapped: Bool) -> UInt32 {
        swapped ? value.byteSwapped : value
    }

    private func normalize(_ value: UInt64, swapped: Bool) -> UInt64 {
        swapped ? value.byteSwapped : value
    }

    private func normalize(_ value: Int32, swapped: Bool) -> Int32 {
        Int32(bitPattern: normalize(UInt32(bitPattern: value), swapped: swapped))
    }

    private func normalize(_ value: Int16, swapped: Bool) -> Int16 {
        Int16(bitPattern: normalize(UInt16(bitPattern: value), swapped: swapped))
    }

    private func normalize(_ value: UInt16, swapped: Bool) -> UInt16 {
        swapped ? value.byteSwapped : value
    }

    private func normalizeSymbolDescription(_ value: UInt16, swapped: Bool) -> UInt16 {
        normalize(value, swapped: swapped)
    }

    private func normalizeSymbolDescription(_ value: Int16, swapped: Bool) -> UInt16 {
        UInt16(bitPattern: normalize(value, swapped: swapped))
    }
}

private struct ParsedHeader {
    let info: MachOHeaderInfo
    let swapped: Bool
    let headerSize: Int
}

private struct ParsedSliceComponents {
    let header: MachOHeaderInfo
    let loadCommands: [MachOLoadCommandInfo]
    let installNameInfo: DylibCommandInfo?
    let dylibReferences: [DylibCommandInfo]
    let rpathCommands: [RPathCommandInfo]
    let buildVersion: BuildVersionInfo?
    let versionMin: VersionMinInfo?
    let segments: [SegmentInfo]
    let symbolTable: SymbolTableInfo?
    let uuid: UUID?
    let codeSignature: LinkEditDataInfo?
    let encryptionInfo: EncryptionInfo?
    let swapped: Bool
}

/// fat 头中的一个架构条目（字段均已转换为主机字节序）。
struct FatArchitectureEntry {
    /// `fat_arch` / `fat_arch_64` 条目本身在文件中的偏移，写回 size 等字段时使用。
    let entryOffset: Int
    let is64Bit: Bool
    let isByteSwapped: Bool
    let cpuType: Int32
    let cpuSubtype: Int32
    /// 切片在文件中的起始偏移。
    let offset: Int
    /// fat 头记录的切片大小（未校验，可能超出文件末尾）。
    let size: UInt64
}

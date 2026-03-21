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

    func parseContainer() throws -> MachOContainer {
        let magic = try read(UInt32.self, at: 0)

        switch magic {
        case FAT_MAGIC, FAT_CIGAM, FAT_MAGIC_64, FAT_CIGAM_64:
            return try parseFatContainer(magic: magic)
        case MH_MAGIC, MH_CIGAM, MH_MAGIC_64, MH_CIGAM_64:
            return MachOContainer(kind: .thin, slices: [try parseSlice(at: 0, magic: magic)])
        default:
            throw MachOParseError.unsupportedMagic(magic)
        }
    }

    private func parseFatContainer(magic: UInt32) throws -> MachOContainer {
        let swapped = magic == FAT_CIGAM || magic == FAT_CIGAM_64
        let is64Bit = magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64
        let header = try read(fat_header.self, at: 0)
        let architectureCount = normalize(header.nfat_arch, swapped: swapped)

        let slices = try (0..<Int(architectureCount)).map { index in
            if is64Bit {
                let architectureOffset = MemoryLayout<fat_header>.size + index * MemoryLayout<fat_arch_64>.size
                let architecture = try read(fat_arch_64.self, at: architectureOffset)
                let sliceOffset = Int(normalize(architecture.offset, swapped: swapped))
                let sliceMagic = try read(UInt32.self, at: sliceOffset)
                return try parseSlice(at: sliceOffset, magic: sliceMagic)
            } else {
                let architectureOffset = MemoryLayout<fat_header>.size + index * MemoryLayout<fat_arch>.size
                let architecture = try read(fat_arch.self, at: architectureOffset)
                let sliceOffset = Int(normalize(architecture.offset, swapped: swapped))
                let sliceMagic = try read(UInt32.self, at: sliceOffset)
                return try parseSlice(at: sliceOffset, magic: sliceMagic)
            }
        }

        return MachOContainer(kind: .fat, slices: slices)
    }

    private func parseSlice(at offset: Int, magic: UInt32) throws -> MachOSlice {
        let parsedHeader = try parseHeader(at: offset, magic: magic)
        let commandsStart = offset + parsedHeader.headerSize
        let commandsEnd = commandsStart + Int(parsedHeader.info.sizeofCommands)
        guard commandsEnd <= data.count else {
            throw MachOParseError.outOfBounds(offset: commandsStart, size: Int(parsedHeader.info.sizeofCommands))
        }

        var cursor = commandsStart
        var loadCommands = [MachOLoadCommandInfo]()
        loadCommands.reserveCapacity(Int(parsedHeader.info.numberOfCommands))
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

        let symbols = try symbolTable.map { try parseSymbols(using: $0, is64Bit: parsedHeader.info.is64Bit, swapped: parsedHeader.swapped) } ?? []

        return MachOSlice(
            offset: offset,
            header: parsedHeader.info,
            loadCommands: loadCommands,
            installNameInfo: installNameInfo,
            dylibReferences: dylibReferences,
            rpathCommands: rpathCommands,
            buildVersion: buildVersion,
            versionMin: versionMin,
            segments: segments,
            symbolTable: symbolTable,
            symbols: symbols,
            uuid: uuid,
            codeSignature: codeSignature,
            encryptionInfo: encryptionInfo
        )
    }

    private func parseLoadCommandPayload(
        commandType: UInt32,
        commandSize: UInt32,
        commandOffset: Int,
        swapped: Bool
    ) throws -> MachOLoadCommandInfo.Payload? {
        switch commandType {
        case UInt32(LC_ID_DYLIB), UInt32(LC_LOAD_DYLIB), UInt32(LC_LOAD_WEAK_DYLIB), UInt32(LC_REEXPORT_DYLIB), UInt32(LC_LOAD_UPWARD_DYLIB):
            return .dylib(try parseDylibCommand(at: commandOffset, swapped: swapped))
        case UInt32(LC_RPATH):
            return .rpath(try parseRPathCommand(at: commandOffset, swapped: swapped))
        case UInt32(LC_BUILD_VERSION):
            return .buildVersion(try parseBuildVersionCommand(at: commandOffset, swapped: swapped))
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

    private func parseBuildVersionCommand(at offset: Int, swapped: Bool) throws -> BuildVersionInfo {
        let command = try read(build_version_command.self, at: offset)
        let toolCount = Int(normalize(command.ntools, swapped: swapped))
        let toolsStart = offset + MemoryLayout<build_version_command>.size
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

    private func parseSymbols(using symbolTable: SymbolTableInfo, is64Bit: Bool, swapped: Bool) throws -> [SymbolInfo] {
        let count = Int(symbolTable.symbolCount)
        let symbolEntrySize = is64Bit ? MemoryLayout<nlist_64>.size : MemoryLayout<nlist>.size
        let symbolsStart = Int(symbolTable.symbolOffset)
        let symbolsSize = count * symbolEntrySize
        guard symbolsStart >= 0, symbolsStart + symbolsSize <= data.count else {
            throw MachOParseError.outOfBounds(offset: symbolsStart, size: symbolsSize)
        }

        let stringTableStart = Int(symbolTable.stringTableOffset)
        let stringTableSize = Int(symbolTable.stringTableSize)
        guard stringTableStart >= 0, stringTableStart + stringTableSize <= data.count else {
            throw MachOParseError.outOfBounds(offset: stringTableStart, size: stringTableSize)
        }

        return try (0..<count).map { index in
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

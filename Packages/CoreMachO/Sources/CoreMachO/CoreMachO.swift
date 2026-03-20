import CoreMachOC
import Foundation

public struct MachOContainer: Sendable {
    public enum Kind: Sendable {
        case thin
        case fat
    }

    public let kind: Kind
    public let slices: [MachOSlice]

    public static func parse(at url: URL) throws -> MachOContainer {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let parser = MachOFileParser(data: data)
        return try parser.parseContainer()
    }
}

public struct MachOSlice: Sendable {
    public let offset: Int
    public let is64Bit: Bool
    public let loadCommands: [MachOLoadCommand]
}

public struct MachOLoadCommand: Sendable {
    public let command: UInt32
    public let size: UInt32
}

public enum MachOParseError: Error {
    case fileTooSmall
    case unsupportedMagic(UInt32)
    case outOfBounds(offset: Int, size: Int)
    case invalidLoadCommandSize(UInt32)
}

private struct MachOFileParser {
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
        let archCount = normalize(header.nfat_arch, swapped: swapped)

        let slices = try (0..<Int(archCount)).map { index in
            if is64Bit {
                let archOffset = MemoryLayout<fat_header>.size + index * MemoryLayout<fat_arch_64>.size
                let arch = try read(fat_arch_64.self, at: archOffset)
                let sliceOffset = Int(normalize(arch.offset, swapped: swapped))
                let sliceMagic = try read(UInt32.self, at: sliceOffset)
                return try parseSlice(at: sliceOffset, magic: sliceMagic)
            } else {
                let archOffset = MemoryLayout<fat_header>.size + index * MemoryLayout<fat_arch>.size
                let arch = try read(fat_arch.self, at: archOffset)
                let sliceOffset = Int(normalize(arch.offset, swapped: swapped))
                let sliceMagic = try read(UInt32.self, at: sliceOffset)
                return try parseSlice(at: sliceOffset, magic: sliceMagic)
            }
        }

        return MachOContainer(kind: .fat, slices: slices)
    }

    private func parseSlice(at offset: Int, magic: UInt32) throws -> MachOSlice {
        let headerInfo = try parseHeader(at: offset, magic: magic)
        let commandsStart = offset + headerInfo.headerSize
        var cursor = commandsStart
        var loadCommands = [MachOLoadCommand]()
        loadCommands.reserveCapacity(Int(headerInfo.numberOfCommands))

        for _ in 0..<headerInfo.numberOfCommands {
            let command = try read(load_command.self, at: cursor)
            let commandType = normalize(command.cmd, swapped: headerInfo.swapped)
            let commandSize = normalize(command.cmdsize, swapped: headerInfo.swapped)

            guard commandSize >= UInt32(MemoryLayout<load_command>.size) else {
                throw MachOParseError.invalidLoadCommandSize(commandSize)
            }

            let endOffset = cursor + Int(commandSize)
            guard endOffset <= data.count else {
                throw MachOParseError.outOfBounds(offset: cursor, size: Int(commandSize))
            }

            loadCommands.append(MachOLoadCommand(command: commandType, size: commandSize))
            cursor = endOffset
        }

        return MachOSlice(
            offset: offset,
            is64Bit: headerInfo.is64Bit,
            loadCommands: loadCommands
        )
    }

    private func parseHeader(at offset: Int, magic: UInt32) throws -> ParsedHeader {
        let swapped = magic == MH_CIGAM || magic == MH_CIGAM_64
        let is64Bit = magic == MH_MAGIC_64 || magic == MH_CIGAM_64

        if is64Bit {
            let header = try read(mach_header_64.self, at: offset)
            return ParsedHeader(
                is64Bit: true,
                swapped: swapped,
                numberOfCommands: normalize(header.ncmds, swapped: swapped),
                sizeofcmds: normalize(header.sizeofcmds, swapped: swapped),
                headerSize: MemoryLayout<mach_header_64>.size
            )
        } else {
            let header = try read(mach_header.self, at: offset)
            return ParsedHeader(
                is64Bit: false,
                swapped: swapped,
                numberOfCommands: normalize(header.ncmds, swapped: swapped),
                sizeofcmds: normalize(header.sizeofcmds, swapped: swapped),
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

    private func normalize(_ value: UInt32, swapped: Bool) -> UInt32 {
        swapped ? value.byteSwapped : value
    }

    private func normalize(_ value: UInt64, swapped: Bool) -> UInt64 {
        swapped ? value.byteSwapped : value
    }
}

private struct ParsedHeader {
    let is64Bit: Bool
    let swapped: Bool
    let numberOfCommands: UInt32
    let sizeofcmds: UInt32
    let headerSize: Int
}

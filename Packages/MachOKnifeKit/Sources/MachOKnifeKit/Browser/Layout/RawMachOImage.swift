import Foundation

/// Byte-level model of one Mach-O image located at `base` inside a mapped file.
///
/// All offsets exposed by this type are absolute file offsets, so a slice of a fat
/// binary or a member of a static archive reports the same offsets MachOView shows.
final class RawMachOImage: @unchecked Sendable {
    struct LoadCommandRecord {
        let index: Int
        let offset: Int
        let cmd: UInt32
        let size: Int
    }

    struct Segment {
        let commandIndex: Int
        let name: String
        let vmaddr: UInt64
        let vmsize: UInt64
        let fileoff: UInt64
        let filesize: UInt64
        let maxprot: Int32
        let initprot: Int32
        let nsects: UInt32
        let flags: UInt32
        let sectionRange: Range<Int>
    }

    struct Section {
        /// 1-based ordinal used by `n_sect`.
        let ordinal: Int
        let headerOffset: Int
        let segmentName: String
        let name: String
        let addr: UInt64
        let size: UInt64
        let offset: UInt32
        let align: UInt32
        let reloff: UInt32
        let nreloc: UInt32
        let flags: UInt32
        let reserved1: UInt32
        let reserved2: UInt32
        let reserved3: UInt32

        var type: UInt32 { flags & MachOConstants.SECTION_TYPE }
        var isZerofill: Bool { MachOConstants.isZerofill(flags) }
        var qualifiedName: String { "\(segmentName),\(name)" }
    }

    struct LinkEditData {
        let cmd: UInt32
        let dataoff: UInt32
        let datasize: UInt32
    }

    struct Symtab {
        let symoff: UInt32
        let nsyms: UInt32
        let stroff: UInt32
        let strsize: UInt32
    }

    struct Dysymtab {
        let ilocalsym: UInt32, nlocalsym: UInt32
        let iextdefsym: UInt32, nextdefsym: UInt32
        let iundefsym: UInt32, nundefsym: UInt32
        let tocoff: UInt32, ntoc: UInt32
        let modtaboff: UInt32, nmodtab: UInt32
        let extrefsymoff: UInt32, nextrefsyms: UInt32
        let indirectsymoff: UInt32, nindirectsyms: UInt32
        let extreloff: UInt32, nextrel: UInt32
        let locreloff: UInt32, nlocrel: UInt32
    }

    struct DyldInfo {
        let rebaseOff: UInt32, rebaseSize: UInt32
        let bindOff: UInt32, bindSize: UInt32
        let weakBindOff: UInt32, weakBindSize: UInt32
        let lazyBindOff: UInt32, lazyBindSize: UInt32
        let exportOff: UInt32, exportSize: UInt32
    }

    struct Symbol {
        let index: Int
        let offset: Int
        let strx: UInt32
        let type: UInt8
        let sect: UInt8
        let desc: UInt16
        let value: UInt64
        let name: String
    }

    let reader: MachOByteReader
    let base: Int
    let limit: Int
    let magic: UInt32
    let is64: Bool
    let swapped: Bool
    let cputype: Int32
    let cpusubtype: Int32
    let filetype: UInt32
    let ncmds: UInt32
    let sizeofcmds: UInt32
    let flags: UInt32
    let reserved: UInt32?

    private(set) var commands: [LoadCommandRecord] = []
    private(set) var segments: [Segment] = []
    private(set) var sections: [Section] = []
    private(set) var symtab: Symtab?
    private(set) var dysymtab: Dysymtab?
    private(set) var dyldInfo: DyldInfo?
    private(set) var linkEditData: [LinkEditData] = []
    private(set) var dylibs: [String] = []
    private(set) var platform: UInt32?
    private(set) var uuid: String?
    private(set) var installName: String?

    var headerSize: Int { is64 ? 32 : 28 }
    var pointerSize: Int { is64 ? 8 : 4 }
    var nlistSize: Int { is64 ? 16 : 12 }
    var size: Int { limit - base }
    var isObject: Bool { filetype == 0x1 }

    var architecture: String { MachOConstants.architectureName(cpuType: cputype, subtype: cpusubtype) }
    var displayArchitecture: String { MachOConstants.displayArchitecture(cpuType: cputype, subtype: cpusubtype) }

    /// Platform name such as `iphoneos`, normalized to the simulator variant for Intel slices
    /// that only carry legacy version-min commands.
    var platformName: String {
        guard let platform else { return "unknown" }
        let name = MachOConstants.shortPlatformName(platform)
        let isIntel = cputype == MachOConstants.CPU_TYPE_X86 || cputype == MachOConstants.CPU_TYPE_X86_64
        guard isIntel, hasBuildVersion == false else { return name }
        switch name {
        case "iphoneos": return "iphonesimulator"
        case "tvos": return "tvossimulator"
        case "watchos": return "watchsimulator"
        default: return name
        }
    }

    var platformArchitectureLabel: String { "\(platformName)_\(displayArchitecture)" }

    private var hasBuildVersion = false
    private let cacheLock = NSRecursiveLock()
    private var cacheStorage: [String: Any] = [:]

    /// Compute-once storage for tables decoded on demand (symbols, bind maps, fixups, ...).
    func cached<T>(_ key: String, _ compute: () -> T) -> T {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        // Look the key up explicitly: `Any? as? T` succeeds with `nil` when `T` is itself
        // optional, which would hide uncomputed entries.
        if let stored = cacheStorage[key], let value = stored as? T {
            return value
        }
        let value = compute()
        cacheStorage[key] = value
        return value
    }

    /// Preferred load address: `__TEXT` vmaddr (0 for object files).
    var imageBase: UInt64 {
        segments.first { $0.name == "__TEXT" }?.vmaddr ?? segments.first { $0.fileoff == 0 && $0.filesize > 0 }?.vmaddr ?? 0
    }

    init?(reader: MachOByteReader, base: Int, limit: Int? = nil) {
        let limit = min(limit ?? reader.size, reader.size)
        guard let rawMagic = reader.u32(at: base) else { return nil }
        switch rawMagic {
        case MachOConstants.MH_MAGIC: is64 = false; swapped = false
        case MachOConstants.MH_MAGIC_64: is64 = true; swapped = false
        case MachOConstants.MH_CIGAM: is64 = false; swapped = true
        case MachOConstants.MH_CIGAM_64: is64 = true; swapped = true
        default: return nil
        }
        guard base + (is64 ? 32 : 28) <= limit else { return nil }
        self.reader = reader
        self.base = base
        self.limit = limit
        self.magic = swapped ? rawMagic.byteSwapped : rawMagic
        self.cputype = Int32(bitPattern: reader.u32(at: base + 4, swapped: swapped) ?? 0)
        self.cpusubtype = Int32(bitPattern: reader.u32(at: base + 8, swapped: swapped) ?? 0)
        self.filetype = reader.u32(at: base + 12, swapped: swapped) ?? 0
        self.ncmds = reader.u32(at: base + 16, swapped: swapped) ?? 0
        self.sizeofcmds = reader.u32(at: base + 20, swapped: swapped) ?? 0
        self.flags = reader.u32(at: base + 24, swapped: swapped) ?? 0
        self.reserved = is64 ? reader.u32(at: base + 28, swapped: swapped) : nil
        parseLoadCommands()
    }

    // MARK: Reading helpers

    func u8(_ offset: Int) -> UInt8 { reader.u8(at: offset) ?? 0 }
    func u16(_ offset: Int) -> UInt16 { reader.u16(at: offset, swapped: swapped) ?? 0 }
    func u32(_ offset: Int) -> UInt32 { reader.u32(at: offset, swapped: swapped) ?? 0 }
    func u64(_ offset: Int) -> UInt64 { reader.u64(at: offset, swapped: swapped) ?? 0 }
    func i32(_ offset: Int) -> Int32 { Int32(bitPattern: u32(offset)) }
    func pointer(_ offset: Int) -> UInt64 { is64 ? u64(offset) : UInt64(u32(offset)) }

    /// Reads an `lc_str` stored inside a load command.
    func loadCommandString(commandOffset: Int, commandSize: Int, fieldOffset: Int) -> String {
        let stringOffset = Int(u32(commandOffset + fieldOffset))
        guard stringOffset < commandSize else { return "" }
        return reader.cString(at: commandOffset + stringOffset, limit: commandOffset + commandSize)?.string ?? ""
    }

    /// Absolute offset of a field expressed relative to the slice start; `nil` when outside the slice.
    func absolute(_ relative: UInt64) -> Int? {
        guard relative <= UInt64(Int.max - base) else { return nil }
        let value = base + Int(relative)
        return value <= limit ? value : nil
    }

    // MARK: Address translation

    /// VM address for an absolute file offset, or `nil` if the offset is not mapped.
    func rva(forFileOffset offset: Int) -> UInt64? {
        let relative = UInt64(max(0, offset - base))
        guard offset >= base else { return nil }
        if isObject {
            for section in sections where section.isZerofill == false && section.size > 0 {
                let start = UInt64(section.offset)
                if relative >= start, relative < start + section.size {
                    return section.addr + (relative - start)
                }
            }
        }
        for segment in segments where segment.filesize > 0 {
            if relative >= segment.fileoff, relative < segment.fileoff + segment.filesize {
                return segment.vmaddr + (relative - segment.fileoff)
            }
        }
        return nil
    }

    /// Absolute file offset backing a VM address, or `nil` for unmapped / zero-fill memory.
    func fileOffset(forVM address: UInt64) -> Int? {
        if isObject || segments.isEmpty {
            for section in sections where section.isZerofill == false {
                if address >= section.addr, address < section.addr + section.size {
                    return absolute(UInt64(section.offset) + (address - section.addr))
                }
            }
            if isObject { return nil }
        }
        for segment in segments where segment.filesize > 0 {
            if address >= segment.vmaddr, address < segment.vmaddr + segment.filesize {
                return absolute(segment.fileoff + (address - segment.vmaddr))
            }
        }
        return nil
    }

    func section(containingVM address: UInt64) -> Section? {
        sections.first { address >= $0.addr && address < $0.addr + max($0.size, 1) }
    }

    func segmentIndex(containingVM address: UInt64) -> Int? {
        segments.firstIndex { address >= $0.vmaddr && address < $0.vmaddr + $0.vmsize }
    }

    func section(ordinal: Int) -> Section? {
        guard ordinal >= 1, ordinal <= sections.count else { return nil }
        return sections[ordinal - 1]
    }

    func section(segment: String, name: String) -> Section? {
        sections.first { $0.segmentName == segment && $0.name == name }
    }

    func linkEdit(_ cmd: UInt32) -> LinkEditData? {
        linkEditData.first { $0.cmd == cmd }
    }

    func cString(atVM address: UInt64) -> String? {
        guard let offset = fileOffset(forVM: address) else { return nil }
        return reader.cString(at: offset, limit: limit)?.string
    }

    // MARK: Symbols

    var symbolTable: [Symbol] {
        cached("symbols") { decodeSymbols() }
    }

    func symbol(at index: Int) -> Symbol? {
        guard let symtab, index >= 0, index < Int(symtab.nsyms) else { return nil }
        guard let offset = absolute(UInt64(symtab.symoff) + UInt64(index * nlistSize)) else { return nil }
        guard reader.contains(offset, count: nlistSize) else { return nil }
        let strx = u32(offset)
        let value = is64 ? u64(offset + 8) : UInt64(u32(offset + 8))
        return Symbol(
            index: index,
            offset: offset,
            strx: strx,
            type: u8(offset + 4),
            sect: u8(offset + 5),
            desc: u16(offset + 6),
            value: value,
            name: string(atStringTableIndex: strx) ?? ""
        )
    }

    func string(atStringTableIndex strx: UInt32) -> String? {
        guard let symtab, strx < symtab.strsize else { return nil }
        guard let start = absolute(UInt64(symtab.stroff)) else { return nil }
        let end = min(limit, start + Int(symtab.strsize))
        return reader.cString(at: start + Int(strx), limit: end)?.string
    }

    private func decodeSymbols() -> [Symbol] {
        guard let symtab else { return [] }
        var result: [Symbol] = []
        result.reserveCapacity(Int(symtab.nsyms))
        for index in 0..<Int(symtab.nsyms) {
            guard let symbol = symbol(at: index) else { break }
            result.append(symbol)
        }
        return result
    }

    /// Best symbol name for an address: defined, non-stab symbols first.
    var addressSymbols: [UInt64: String] {
        cached("addressSymbols") { self.buildAddressSymbols() }
    }

    private func buildAddressSymbols() -> [UInt64: String] {
        var map: [UInt64: String] = [:]
        for symbol in symbolTable where symbol.type & MachOConstants.N_STAB == 0 && symbol.type & MachOConstants.N_TYPE == 0xE {
            if symbol.name.isEmpty == false, map[symbol.value] == nil {
                map[symbol.value] = symbol.name
            }
        }
        return map
    }

    func symbolName(forVM address: UInt64) -> String? {
        addressSymbols[address]
    }

    /// Name of the symbol referenced by an indirect symbol table entry.
    func indirectSymbolName(_ entry: UInt32) -> String {
        if entry & MachOConstants.INDIRECT_SYMBOL_LOCAL != 0 {
            return entry & MachOConstants.INDIRECT_SYMBOL_ABS != 0 ? "INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS" : "INDIRECT_SYMBOL_LOCAL"
        }
        if entry & MachOConstants.INDIRECT_SYMBOL_ABS != 0 {
            return "INDIRECT_SYMBOL_ABS"
        }
        return symbol(at: Int(entry))?.name ?? "?"
    }

    func indirectSymbolEntry(_ index: Int) -> (offset: Int, value: UInt32)? {
        guard let dysymtab, index >= 0, index < Int(dysymtab.nindirectsyms) else { return nil }
        guard let offset = absolute(UInt64(dysymtab.indirectsymoff) + UInt64(index * 4)), reader.contains(offset, count: 4) else {
            return nil
        }
        return (offset, u32(offset))
    }

    // MARK: Load commands

    private func parseLoadCommands() {
        var cursor = base + headerSize
        let commandsEnd = min(limit, cursor + Int(sizeofcmds))
        var sectionOrdinal = 1
        for index in 0..<Int(ncmds) {
            guard cursor + 8 <= commandsEnd else { break }
            let cmd = u32(cursor)
            let size = Int(u32(cursor + 4))
            guard size >= 8, cursor + size <= commandsEnd else {
                commands.append(LoadCommandRecord(index: index, offset: cursor, cmd: cmd, size: max(8, min(size, commandsEnd - cursor))))
                break
            }
            commands.append(LoadCommandRecord(index: index, offset: cursor, cmd: cmd, size: size))
            parse(command: cmd, at: cursor, size: size, index: index, sectionOrdinal: &sectionOrdinal)
            cursor += size
        }
    }

    private func parse(command cmd: UInt32, at offset: Int, size: Int, index: Int, sectionOrdinal: inout Int) {
        switch cmd {
        case 0x1, 0x19:
            let wide = cmd == 0x19
            let name = reader.fixedString(at: offset + 8, count: 16) ?? ""
            let vmaddr = wide ? u64(offset + 24) : UInt64(u32(offset + 24))
            let vmsize = wide ? u64(offset + 32) : UInt64(u32(offset + 28))
            let fileoff = wide ? u64(offset + 40) : UInt64(u32(offset + 32))
            let filesize = wide ? u64(offset + 48) : UInt64(u32(offset + 36))
            let maxprot = i32(offset + (wide ? 56 : 40))
            let initprot = i32(offset + (wide ? 60 : 44))
            let nsects = u32(offset + (wide ? 64 : 48))
            let segFlags = u32(offset + (wide ? 68 : 52))
            let headerSize = wide ? 72 : 56
            let sectionSize = wide ? 80 : 68
            let first = sections.count
            for sectionIndex in 0..<Int(nsects) {
                let sectionOffset = offset + headerSize + sectionIndex * sectionSize
                guard sectionOffset + sectionSize <= offset + size else { break }
                let addr = wide ? u64(sectionOffset + 32) : UInt64(u32(sectionOffset + 32))
                let sectionBytes = wide ? u64(sectionOffset + 40) : UInt64(u32(sectionOffset + 36))
                let fieldBase = sectionOffset + (wide ? 48 : 40)
                sections.append(Section(
                    ordinal: sectionOrdinal,
                    headerOffset: sectionOffset,
                    segmentName: reader.fixedString(at: sectionOffset + 16, count: 16) ?? "",
                    name: reader.fixedString(at: sectionOffset, count: 16) ?? "",
                    addr: addr,
                    size: sectionBytes,
                    offset: u32(fieldBase),
                    align: u32(fieldBase + 4),
                    reloff: u32(fieldBase + 8),
                    nreloc: u32(fieldBase + 12),
                    flags: u32(fieldBase + 16),
                    reserved1: u32(fieldBase + 20),
                    reserved2: u32(fieldBase + 24),
                    reserved3: wide ? u32(fieldBase + 28) : 0
                ))
                sectionOrdinal += 1
            }
            segments.append(Segment(
                commandIndex: index,
                name: name,
                vmaddr: vmaddr,
                vmsize: vmsize,
                fileoff: fileoff,
                filesize: filesize,
                maxprot: maxprot,
                initprot: initprot,
                nsects: nsects,
                flags: segFlags,
                sectionRange: first..<sections.count
            ))
        case 0x2:
            symtab = Symtab(symoff: u32(offset + 8), nsyms: u32(offset + 12), stroff: u32(offset + 16), strsize: u32(offset + 20))
        case 0xB:
            let f = (0..<18).map { u32(offset + 8 + $0 * 4) }
            dysymtab = Dysymtab(
                ilocalsym: f[0], nlocalsym: f[1], iextdefsym: f[2], nextdefsym: f[3], iundefsym: f[4], nundefsym: f[5],
                tocoff: f[6], ntoc: f[7], modtaboff: f[8], nmodtab: f[9], extrefsymoff: f[10], nextrefsyms: f[11],
                indirectsymoff: f[12], nindirectsyms: f[13], extreloff: f[14], nextrel: f[15], locreloff: f[16], nlocrel: f[17]
            )
        case 0x22, 0x22 | MachOConstants.LC_REQ_DYLD:
            let f = (0..<10).map { u32(offset + 8 + $0 * 4) }
            dyldInfo = DyldInfo(
                rebaseOff: f[0], rebaseSize: f[1], bindOff: f[2], bindSize: f[3], weakBindOff: f[4], weakBindSize: f[5],
                lazyBindOff: f[6], lazyBindSize: f[7], exportOff: f[8], exportSize: f[9]
            )
        case 0xC, 0x18 | MachOConstants.LC_REQ_DYLD, 0x1F | MachOConstants.LC_REQ_DYLD, 0x20, 0x23 | MachOConstants.LC_REQ_DYLD:
            dylibs.append(loadCommandString(commandOffset: offset, commandSize: size, fieldOffset: 8))
        case 0xD:
            installName = loadCommandString(commandOffset: offset, commandSize: size, fieldOffset: 8)
        case 0x1B:
            if let bytes = reader.bytes(at: offset + 8, count: 16) {
                uuid = Self.formatUUID(bytes)
            }
        case 0x24:
            if platform == nil { platform = 1 }
        case 0x25:
            if platform == nil { platform = 2 }
        case 0x2F:
            if platform == nil { platform = 3 }
        case 0x30:
            if platform == nil { platform = 4 }
        case 0x32:
            if hasBuildVersion == false {
                platform = u32(offset + 8)
                hasBuildVersion = true
            }
        case 0x1D, 0x1E, 0x26, 0x29, 0x2B, 0x2E, 0x33 | MachOConstants.LC_REQ_DYLD, 0x34 | MachOConstants.LC_REQ_DYLD, 0x36, 0x37, 0x38:
            linkEditData.append(LinkEditData(cmd: cmd, dataoff: u32(offset + 8), datasize: u32(offset + 12)))
        default:
            break
        }
    }

    static func formatUUID(_ bytes: Data) -> String {
        let hex = bytes.map { String(format: "%02X", $0) }
        guard hex.count == 16 else { return hex.joined() }
        return [hex[0..<4], hex[4..<6], hex[6..<8], hex[8..<10], hex[10..<16]].map { $0.joined() }.joined(separator: "-")
    }
}

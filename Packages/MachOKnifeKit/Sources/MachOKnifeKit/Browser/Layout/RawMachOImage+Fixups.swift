import Foundation

/// What a pointer-sized slot resolves to once relocations, chained fixups or binds are applied.
enum ResolvedPointer {
    case null
    case address(UInt64)
    case bind(name: String, addend: Int64)

    var address: UInt64? {
        if case let .address(value) = self { return value }
        return nil
    }
}

extension RawMachOImage {
    // MARK: Chained fixups model

    struct ChainedImport {
        let index: Int
        let offset: Int
        let libraryOrdinal: Int
        let weak: Bool
        let nameOffset: UInt32
        let addend: Int64
        let name: String
    }

    struct ChainedSegmentStarts {
        let segmentIndex: Int
        let offset: Int
        let size: UInt32
        let pageSize: UInt16
        let pointerFormat: UInt16
        let segmentOffset: UInt64
        let maxValidPointer: UInt32
        let pageCount: UInt16
        let pageStartsOffset: Int
    }

    struct ChainedFixup {
        enum Kind {
            case rebase(target: UInt64)
            case bind(ordinal: Int, addend: Int64)
        }

        let offset: Int
        let raw: UInt64
        let format: UInt16
        let kind: Kind
        let next: UInt64
        let auth: (key: UInt8, diversity: UInt16, addressDiversity: Bool)?
    }

    struct ChainedFixups {
        let headerOffset: Int
        let end: Int
        let importsFormat: UInt32
        let symbolsOffset: Int
        let imports: [ChainedImport]
        let segments: [ChainedSegmentStarts]
        let startsOffset: Int
        let fixups: [ChainedFixup]
        let fixupsByOffset: [Int: Int]
    }

    var chainedFixups: ChainedFixups? {
        cached("chainedFixups") { decodeChainedFixups() }
    }

    private func decodeChainedFixups() -> ChainedFixups? {
        guard let command = linkEdit(0x34 | MachOConstants.LC_REQ_DYLD), command.datasize >= 28,
              let header = absolute(UInt64(command.dataoff)) else {
            return nil
        }
        let end = min(limit, header + Int(command.datasize))
        let startsOffset = header + Int(u32(header + 4))
        let importsOffset = header + Int(u32(header + 8))
        let symbolsOffset = header + Int(u32(header + 12))
        let importsCount = Int(u32(header + 16))
        let importsFormat = u32(header + 20)

        var imports: [ChainedImport] = []
        imports.reserveCapacity(importsCount)
        for index in 0..<importsCount {
            let entrySize = importsFormat == 3 ? 16 : (importsFormat == 2 ? 8 : 4)
            let offset = importsOffset + index * entrySize
            guard offset + entrySize <= end else { break }
            var ordinal: Int
            let weak: Bool
            let nameOffset: UInt32
            var addend: Int64 = 0
            if importsFormat == 3 {
                let raw = u64(offset)
                ordinal = Int(raw & 0xFFFF)
                if ordinal > 0xFFF0 { ordinal -= 0x10000 }
                weak = (raw >> 16) & 1 == 1
                nameOffset = UInt32(truncatingIfNeeded: raw >> 32)
                addend = Int64(bitPattern: u64(offset + 8))
            } else {
                let raw = u32(offset)
                ordinal = Int(raw & 0xFF)
                if ordinal > 0xF0 { ordinal -= 0x100 }
                weak = (raw >> 8) & 1 == 1
                nameOffset = raw >> 9
                if importsFormat == 2 {
                    addend = Int64(i32(offset + 4))
                }
            }
            let name = reader.cString(at: symbolsOffset + Int(nameOffset), limit: end)?.string ?? ""
            imports.append(ChainedImport(index: index, offset: offset, libraryOrdinal: ordinal, weak: weak, nameOffset: nameOffset, addend: addend, name: name))
        }

        var segmentStarts: [ChainedSegmentStarts] = []
        let segmentCount = Int(u32(startsOffset))
        for index in 0..<segmentCount {
            let infoOffset = u32(startsOffset + 4 + index * 4)
            guard infoOffset != 0 else { continue }
            let offset = startsOffset + Int(infoOffset)
            guard offset + 22 <= end else { continue }
            segmentStarts.append(ChainedSegmentStarts(
                segmentIndex: index,
                offset: offset,
                size: u32(offset),
                pageSize: u16(offset + 4),
                pointerFormat: u16(offset + 6),
                segmentOffset: u64(offset + 8),
                maxValidPointer: u32(offset + 16),
                pageCount: u16(offset + 20),
                pageStartsOffset: offset + 22
            ))
        }

        var fixups: [ChainedFixup] = []
        for starts in segmentStarts where starts.segmentIndex < segments.count {
            let segment = segments[starts.segmentIndex]
            guard let segmentStart = absolute(segment.fileoff) else { continue }
            for page in 0..<Int(starts.pageCount) {
                let start = u16(starts.pageStartsOffset + page * 2)
                if start == 0xFFFF { continue }
                let pageBase = segmentStart + page * Int(starts.pageSize)
                if start & 0x8000 != 0, [3, 4, 5].contains(starts.pointerFormat) {
                    // DYLD_CHAINED_PTR_START_MULTI: overflow list of chain starts.
                    var overflowIndex = Int(start & ~0x8000)
                    while true {
                        let entry = u16(starts.pageStartsOffset + overflowIndex * 2)
                        walkChain(from: pageBase + Int(entry & ~0x8000), format: starts.pointerFormat, limit: min(limit, segmentStart + Int(segment.filesize)), into: &fixups)
                        if entry & 0x8000 != 0 || overflowIndex > Int(starts.size) { break }
                        overflowIndex += 1
                    }
                } else {
                    walkChain(from: pageBase + Int(start), format: starts.pointerFormat, limit: min(limit, segmentStart + Int(segment.filesize)), into: &fixups)
                }
            }
        }

        var byOffset: [Int: Int] = [:]
        byOffset.reserveCapacity(fixups.count)
        for (index, fixup) in fixups.enumerated() {
            byOffset[fixup.offset] = index
        }
        return ChainedFixups(
            headerOffset: header,
            end: end,
            importsFormat: importsFormat,
            symbolsOffset: symbolsOffset,
            imports: imports,
            segments: segmentStarts,
            startsOffset: startsOffset,
            fixups: fixups,
            fixupsByOffset: byOffset
        )
    }

    private func walkChain(from start: Int, format: UInt16, limit chainLimit: Int, into fixups: inout [ChainedFixup]) {
        var location = start
        let stride = MachOConstants.chainedPointerStride(format)
        var guardCount = 0
        while location >= base, location + (format == 3 ? 4 : 8) <= chainLimit, guardCount < 1_000_000 {
            guardCount += 1
            guard let fixup = decodeChainedPointer(at: location, format: format) else { return }
            fixups.append(fixup)
            if fixup.next == 0 { return }
            location += Int(fixup.next) * stride
        }
    }

    func decodeChainedPointer(at offset: Int, format: UInt16) -> ChainedFixup? {
        func bits(_ value: UInt64, _ shift: UInt64, _ count: UInt64) -> UInt64 {
            (value >> shift) & ((1 << count) - 1)
        }
        func signExtend(_ value: UInt64, _ count: UInt64) -> Int64 {
            let shift = 64 - count
            return Int64(bitPattern: value << shift) >> Int64(shift)
        }

        switch format {
        case 1, 7, 9, 10, 12:
            let raw = u64(offset)
            let isAuth = raw >> 63 == 1
            let isBind = (raw >> 62) & 1 == 1
            let next = bits(raw, 51, 11)
            let ordinalBits: UInt64 = format == 12 ? 24 : 16
            let offsetTargets = format != 1
            if isAuth {
                let auth = (key: UInt8(bits(raw, 49, 2)), diversity: UInt16(bits(raw, 32, 16)), addressDiversity: bits(raw, 48, 1) == 1)
                if isBind {
                    return ChainedFixup(offset: offset, raw: raw, format: format, kind: .bind(ordinal: Int(bits(raw, 0, ordinalBits)), addend: 0), next: next, auth: auth)
                }
                return ChainedFixup(offset: offset, raw: raw, format: format, kind: .rebase(target: imageBase + bits(raw, 0, 32)), next: next, auth: auth)
            }
            if isBind {
                let addend = signExtend(bits(raw, 32, 19), 19)
                return ChainedFixup(offset: offset, raw: raw, format: format, kind: .bind(ordinal: Int(bits(raw, 0, ordinalBits)), addend: addend), next: next, auth: nil)
            }
            let target = bits(raw, 0, 43)
            return ChainedFixup(offset: offset, raw: raw, format: format, kind: .rebase(target: offsetTargets ? imageBase + target : target), next: next, auth: nil)
        case 2, 6:
            let raw = u64(offset)
            let next = bits(raw, 51, 12)
            if raw >> 63 == 1 {
                return ChainedFixup(offset: offset, raw: raw, format: format, kind: .bind(ordinal: Int(bits(raw, 0, 24)), addend: Int64(bits(raw, 24, 8))), next: next, auth: nil)
            }
            let target = bits(raw, 0, 36)
            return ChainedFixup(offset: offset, raw: raw, format: format, kind: .rebase(target: format == 6 ? imageBase + target : target), next: next, auth: nil)
        case 8, 11:
            let raw = u64(offset)
            let next = bits(raw, 51, 12)
            let auth = bits(raw, 63, 1) == 1
                ? (key: UInt8(bits(raw, 49, 2)), diversity: UInt16(bits(raw, 32, 16)), addressDiversity: bits(raw, 48, 1) == 1)
                : nil
            return ChainedFixup(offset: offset, raw: raw, format: format, kind: .rebase(target: imageBase + bits(raw, 0, 30)), next: next, auth: auth)
        case 3:
            let raw = UInt64(u32(offset))
            let next = bits(raw, 26, 5)
            if raw >> 31 == 1 {
                return ChainedFixup(offset: offset, raw: raw, format: format, kind: .bind(ordinal: Int(bits(raw, 0, 20)), addend: Int64(bits(raw, 20, 6))), next: next, auth: nil)
            }
            return ChainedFixup(offset: offset, raw: raw, format: format, kind: .rebase(target: bits(raw, 0, 26)), next: next, auth: nil)
        default:
            return nil
        }
    }

    // MARK: Legacy dyld info

    struct BindAction {
        enum Kind: String {
            case bind = "Bind"
            case weak = "Weak Bind"
            case lazy = "Lazy Bind"
        }

        let kind: Kind
        let opcodeOffset: Int
        let segmentIndex: Int
        let segmentOffset: UInt64
        let address: UInt64
        let type: UInt8
        let ordinal: Int
        let symbol: String
        let addend: Int64
        let flags: UInt8
    }

    struct RebaseAction {
        let opcodeOffset: Int
        let segmentIndex: Int
        let address: UInt64
        let type: UInt8
    }

    func segmentAddress(_ index: Int, _ offset: UInt64) -> UInt64 {
        guard index >= 0, index < segments.count else { return offset }
        return segments[index].vmaddr &+ offset
    }

    var rebaseActions: [RebaseAction] {
        cached("rebaseActions") { decodeRebases() }
    }

    private func decodeRebases() -> [RebaseAction] {
        guard let info = dyldInfo, info.rebaseSize > 0, let start = absolute(UInt64(info.rebaseOff)) else { return [] }
        let end = min(limit, start + Int(info.rebaseSize))
        var cursor = start
        var type: UInt8 = 0
        var segment = 0
        var segOffset: UInt64 = 0
        var actions: [RebaseAction] = []
        let pointer = UInt64(pointerSize)
        loop: while cursor < end {
            let opcodeOffset = cursor
            let byte = u8(cursor)
            cursor += 1
            let immediate = byte & 0x0F
            func uleb() -> UInt64 {
                guard let value = reader.uleb128(at: cursor, limit: end) else { cursor = end; return 0 }
                cursor += value.length
                return value.value
            }
            func emit() {
                actions.append(RebaseAction(opcodeOffset: opcodeOffset, segmentIndex: segment, address: segmentAddress(segment, segOffset), type: type))
            }
            switch byte & 0xF0 {
            case 0x00: break loop
            case 0x10: type = immediate
            case 0x20: segment = Int(immediate); segOffset = uleb()
            case 0x30: segOffset &+= uleb()
            case 0x40: segOffset &+= UInt64(immediate) * pointer
            case 0x50:
                for _ in 0..<immediate { emit(); segOffset &+= pointer }
            case 0x60:
                let count = uleb()
                for _ in 0..<min(count, 10_000_000) { emit(); segOffset &+= pointer }
            case 0x70:
                emit(); segOffset &+= uleb() &+ pointer
            case 0x80:
                let count = uleb()
                let skip = uleb()
                for _ in 0..<min(count, 10_000_000) { emit(); segOffset &+= skip &+ pointer }
            default: break loop
            }
        }
        return actions
    }

    var bindActions: [BindAction] {
        cached("bindActions") {
            guard let info = dyldInfo else { return [] }
            return decodeBinds(info.bindOff, info.bindSize, .bind)
                + decodeBinds(info.weakBindOff, info.weakBindSize, .weak)
                + decodeBinds(info.lazyBindOff, info.lazyBindSize, .lazy)
        }
    }

    private func decodeBinds(_ offset: UInt32, _ size: UInt32, _ kind: BindAction.Kind) -> [BindAction] {
        guard size > 0, let start = absolute(UInt64(offset)) else { return [] }
        let end = min(limit, start + Int(size))
        var cursor = start
        var ordinal = 0
        var symbol = ""
        var flags: UInt8 = 0
        var type: UInt8 = 1
        var addend: Int64 = 0
        var segment = 0
        var segOffset: UInt64 = 0
        var actions: [BindAction] = []
        let pointer = UInt64(pointerSize)
        while cursor < end {
            let opcodeOffset = cursor
            let byte = u8(cursor)
            cursor += 1
            let immediate = byte & 0x0F
            func uleb() -> UInt64 {
                guard let value = reader.uleb128(at: cursor, limit: end) else { cursor = end; return 0 }
                cursor += value.length
                return value.value
            }
            func emit() {
                actions.append(BindAction(
                    kind: kind, opcodeOffset: opcodeOffset, segmentIndex: segment, segmentOffset: segOffset,
                    address: segmentAddress(segment, segOffset), type: type, ordinal: ordinal, symbol: symbol, addend: addend, flags: flags
                ))
            }
            switch byte & 0xF0 {
            case 0x00:
                // Lazy bind streams separate entries with DONE opcodes.
                if kind != .lazy { cursor = end }
            case 0x10: ordinal = Int(immediate)
            case 0x20: ordinal = Int(uleb())
            case 0x30: ordinal = immediate == 0 ? 0 : Int(Int8(bitPattern: 0xF0 | immediate))
            case 0x40:
                flags = immediate
                if let decoded = reader.cString(at: cursor, limit: end) {
                    symbol = decoded.string
                    cursor += decoded.length + 1
                } else {
                    cursor = end
                }
            case 0x50: type = immediate
            case 0x60:
                if let value = reader.sleb128(at: cursor, limit: end) { addend = value.value; cursor += value.length } else { cursor = end }
            case 0x70: segment = Int(immediate); segOffset = uleb()
            case 0x80: segOffset &+= uleb()
            case 0x90: emit(); segOffset &+= pointer
            case 0xA0: emit(); segOffset &+= uleb() &+ pointer
            case 0xB0: emit(); segOffset &+= UInt64(immediate) * pointer &+ pointer
            case 0xC0:
                let count = uleb()
                let skip = uleb()
                for _ in 0..<min(count, 10_000_000) { emit(); segOffset &+= skip &+ pointer }
            case 0xD0:
                if immediate == 0 { _ = uleb() }
            default:
                cursor = end
            }
        }
        return actions
    }

    /// VM address → bound symbol from legacy bind opcodes and external relocations.
    var boundAddresses: [UInt64: String] {
        cached("boundAddresses") {
            var map: [UInt64: String] = [:]
            for action in bindActions where map[action.address] == nil {
                map[action.address] = action.symbol
            }
            for relocation in externalRelocations where relocation.isExtern && relocation.isScattered == false {
                let address = externalRelocationBase &+ UInt64(UInt32(bitPattern: relocation.address))
                if map[address] == nil, let symbol = symbol(at: Int(relocation.symbolNum)) {
                    map[address] = symbol.name
                }
            }
            return map
        }
    }

    // MARK: Relocations

    struct Relocation {
        let offset: Int
        let address: Int32
        let symbolNum: UInt32
        let pcRelative: Bool
        let length: UInt8
        let isExtern: Bool
        let type: UInt8
        let isScattered: Bool
        let scatteredValue: UInt32
    }

    func relocations(at offset: UInt32, count: UInt32) -> [Relocation] {
        guard count > 0, let start = absolute(UInt64(offset)) else { return [] }
        var result: [Relocation] = []
        result.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            let entry = start + index * 8
            guard entry + 8 <= limit else { break }
            result.append(relocation(at: entry))
        }
        return result
    }

    func relocation(at entry: Int) -> Relocation {
        let word0 = u32(entry)
        let word1 = u32(entry + 4)
        if word0 & 0x8000_0000 != 0, is64 == false {
            return Relocation(
                offset: entry,
                address: Int32(word0 & 0x00FF_FFFF),
                symbolNum: 0,
                pcRelative: (word0 >> 30) & 1 == 1,
                length: UInt8((word0 >> 28) & 3),
                isExtern: false,
                type: UInt8((word0 >> 24) & 0xF),
                isScattered: true,
                scatteredValue: word1
            )
        }
        return Relocation(
            offset: entry,
            address: Int32(bitPattern: word0),
            symbolNum: word1 & 0x00FF_FFFF,
            pcRelative: (word1 >> 24) & 1 == 1,
            length: UInt8((word1 >> 25) & 3),
            isExtern: (word1 >> 27) & 1 == 1,
            type: UInt8(word1 >> 28),
            isScattered: false,
            scatteredValue: 0
        )
    }

    var externalRelocations: [Relocation] {
        cached("externalRelocations") {
            guard let dysymtab else { return [] }
            return relocations(at: dysymtab.extreloff, count: dysymtab.nextrel)
        }
    }

    /// r_address in linked images is relative to the first segment, or the first writable segment on x86_64.
    var externalRelocationBase: UInt64 {
        if cputype == MachOConstants.CPU_TYPE_X86_64,
           let writable = segments.first(where: { UInt32(bitPattern: $0.initprot) & 2 != 0 }) {
            return writable.vmaddr
        }
        return segments.first?.vmaddr ?? 0
    }

    /// Relocations of an object-file section keyed by absolute file offset of the fixed-up slot.
    func sectionRelocations(_ section: Section) -> [Int: Relocation] {
        cached("relocs-\(section.ordinal)") {
            var map: [Int: Relocation] = [:]
            guard let sectionStart = absolute(UInt64(section.offset)) else { return map }
            for relocation in relocations(at: section.reloff, count: section.nreloc) where relocation.isScattered == false {
                // Skip the subtractor half of a pair; the following entry carries the real target.
                if relocation.type == 5, cputype == MachOConstants.CPU_TYPE_X86_64 { continue }
                if relocation.type == 1, cputype == MachOConstants.CPU_TYPE_ARM64 { continue }
                let slot = sectionStart + Int(relocation.address)
                if map[slot] == nil { map[slot] = relocation }
            }
            return map
        }
    }

    // MARK: Pointer resolution

    func chainedImportName(_ ordinal: Int) -> String {
        guard let fixups = chainedFixups, ordinal >= 0, ordinal < fixups.imports.count else { return "import #\(ordinal)" }
        return fixups.imports[ordinal].name
    }

    func resolvePointer(at offset: Int) -> ResolvedPointer {
        let raw = pointer(offset)
        if isObject {
            if let section = sections.first(where: { section in
                guard section.isZerofill == false, let start = absolute(UInt64(section.offset)) else { return false }
                return offset >= start && offset < start + Int(section.size)
            }), let relocation = sectionRelocations(section)[offset] {
                if relocation.isExtern {
                    guard let symbol = symbol(at: Int(relocation.symbolNum)) else { return .bind(name: "?", addend: Int64(bitPattern: raw)) }
                    if symbol.type & MachOConstants.N_TYPE == 0xE {
                        return .address(symbol.value &+ raw)
                    }
                    return .bind(name: symbol.name, addend: Int64(bitPattern: raw))
                }
                return .address(raw)
            }
            return raw == 0 ? .null : .address(raw)
        }
        if let fixups = chainedFixups {
            if let index = fixups.fixupsByOffset[offset] {
                switch fixups.fixups[index].kind {
                case let .rebase(target):
                    return .address(target)
                case let .bind(ordinal, addend):
                    let importAddend = ordinal < fixups.imports.count ? fixups.imports[ordinal].addend : 0
                    return .bind(name: chainedImportName(ordinal), addend: addend + importAddend)
                }
            }
            return raw == 0 ? .null : .address(raw)
        }
        if let address = rva(forFileOffset: offset), let name = boundAddresses[address] {
            return .bind(name: name, addend: 0)
        }
        if raw == 0 { return .null }
        // Pre-chained arm64e images may still carry threaded rebases.
        if cputype == MachOConstants.CPU_TYPE_ARM64, raw >> 62 != 0, let fixup = decodeChainedPointer(at: offset, format: 1),
           case let .rebase(target) = fixup.kind {
            return .address(target)
        }
        return .address(raw)
    }

    /// Display text for a resolved pointer: symbol name, string target, or address.
    func describe(_ pointer: ResolvedPointer) -> String {
        switch pointer {
        case .null:
            return "0x0"
        case let .bind(name, addend):
            return addend == 0 ? name : "\(name) + \(addend)"
        case let .address(address):
            if let name = symbolName(forVM: address) {
                return "\(hex(address)) (\(name))"
            }
            return hex(address)
        }
    }
}

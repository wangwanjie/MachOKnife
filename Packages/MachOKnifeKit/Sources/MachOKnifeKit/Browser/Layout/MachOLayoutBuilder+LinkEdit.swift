import Foundation

extension MachOLayoutBuilder {
    /// Link-edit structures ordered by file offset, like MachOView lists them after the sections.
    func linkEditChildren() -> [() -> BrowserNode] {
        var entries: [(offset: Int, build: () -> BrowserNode)] = []
        func add(_ offset: UInt32, _ size: UInt32, _ build: @escaping () -> BrowserNode) {
            guard size > 0 else { return }
            entries.append((Int(offset), build))
        }

        if let info = slice.dyldInfo {
            let starts = [info.rebaseOff, info.bindOff, info.weakBindOff, info.lazyBindOff, info.exportOff].filter { $0 > 0 }
            let total = info.rebaseSize + info.bindSize + info.weakBindSize + info.lazyBindSize + info.exportSize
            add(starts.min() ?? 0, total) { dyldInfoNode(info) }
        }
        for data in slice.linkEditData {
            switch data.cmd {
            case 0x34 | MachOConstants.LC_REQ_DYLD:
                add(data.dataoff, data.datasize) { chainedFixupsNode(data) }
            case 0x33 | MachOConstants.LC_REQ_DYLD:
                add(data.dataoff, data.datasize) { exportTrieNode(id: id("exports"), title: "Exports Trie", offset: data.dataoff, size: data.datasize) }
            case 0x26:
                add(data.dataoff, data.datasize) { functionStartsNode(data) }
            case 0x29:
                add(data.dataoff, data.datasize) { dataInCodeNode(data) }
            case 0x1D:
                add(data.dataoff, data.datasize) { codeSignatureNode(data) }
            case 0x2E:
                add(data.dataoff, data.datasize) { linkerOptimizationHintsNode(data) }
            default:
                add(data.dataoff, data.datasize) { rawLinkEditNode(data) }
            }
        }
        if let symtab = slice.symtab {
            add(symtab.symoff, symtab.nsyms * UInt32(slice.nlistSize)) { symbolTableNode(symtab) }
            add(symtab.stroff, symtab.strsize) { stringTableNode(symtab) }
        }
        if let dysymtab = slice.dysymtab {
            let pieces: [(UInt32, UInt32)] = [
                (dysymtab.indirectsymoff, dysymtab.nindirectsyms * 4),
                (dysymtab.extreloff, dysymtab.nextrel * 8),
                (dysymtab.locreloff, dysymtab.nlocrel * 8),
                (dysymtab.tocoff, dysymtab.ntoc * 8),
                (dysymtab.extrefsymoff, dysymtab.nextrefsyms * 4),
                (dysymtab.modtaboff, dysymtab.nmodtab * (slice.is64 ? 56 : 52)),
            ].filter { $0.1 > 0 }
            if let first = pieces.map(\.0).min() {
                add(first, 1) { dynamicSymbolTableNode(dysymtab) }
            }
        }
        return entries.sorted { $0.offset < $1.offset }.map(\.build)
    }

    static func linkEditTitle(_ cmd: UInt32) -> String {
        switch cmd {
        case 0x1D: return "Code Signature"
        case 0x1E: return "Segment Split Info"
        case 0x26: return "Function Starts"
        case 0x29: return "Data in Code Entries"
        case 0x2B: return "Dylib Code Signing DRs"
        case 0x2E: return "Linker Optimization Hints"
        case 0x33 | MachOConstants.LC_REQ_DYLD: return "Exports Trie"
        case 0x34 | MachOConstants.LC_REQ_DYLD: return "Chained Fixups"
        case 0x36: return "Atom Info"
        case 0x37: return "Function Variants"
        case 0x38: return "Function Variant Fixups"
        default: return MachOConstants.loadCommandName(cmd)
        }
    }

    func rawLinkEditNode(_ data: RawMachOImage.LinkEditData) -> BrowserNode {
        let dataRange = linkEditRange(data.dataoff, data.datasize)
        let content = dataRange.map { hexDumpContent(start: $0.offset, length: $0.length) } ?? .empty
        return factory.indexedNode(
            id: id("linkedit", "\(data.cmd)"),
            title: Self.linkEditTitle(data.cmd),
            range: dataRange,
            rowCount: content.count,
            row: content.row
        )
    }

    // MARK: Symbol table

    func symbolTableNode(_ symtab: RawMachOImage.Symtab) -> BrowserNode {
        let slice = slice
        let count = Int(symtab.nsyms)
        let rowsPerSymbol = 5
        let dylibs = slice.dylibs
        let twoLevel = slice.flags & 0x80 != 0
        return factory.indexedNode(
            id: id("symtab"),
            title: "Symbol Table (\(count))",
            range: linkEditRange(symtab.symoff, symtab.nsyms * UInt32(slice.nlistSize)),
            rowCount: count * rowsPerSymbol,
            row: { index in
                let group = UInt(index / rowsPerSymbol)
                guard let symbol = slice.symbol(at: index / rowsPerSymbol) else {
                    return BrowserDetailRow(key: "Invalid Symbol", value: "", groupIdentifier: group)
                }
                let offset = symbol.offset
                switch index % rowsPerSymbol {
                case 0:
                    let name = symbol.name.isEmpty && symbol.strx >= (slice.symtab?.strsize ?? 0) ? "<invalid string index>" : symbol.name
                    return layoutRow(slice, offset, 4, "String Table Index", name, group: group)
                case 1:
                    return layoutRow(slice, offset + 4, 1, "Type", Self.symbolTypeDescription(symbol.type), group: group)
                case 2:
                    let value: String
                    if symbol.sect == 0 {
                        value = "NO_SECT"
                    } else {
                        value = "\(symbol.sect) (\(slice.section(ordinal: Int(symbol.sect))?.qualifiedName ?? "?"))"
                    }
                    return layoutRow(slice, offset + 5, 1, "Section", value, group: group)
                case 3:
                    return layoutRow(slice, offset + 6, 2, "Description", Self.symbolDescription(symbol, twoLevel: twoLevel, dylibs: dylibs), group: group)
                default:
                    return layoutRow(slice, offset + 8, slice.is64 ? 8 : 4, "Value", hex(symbol.value), group: group)
                }
            }
        )
    }

    static func symbolTypeDescription(_ type: UInt8) -> String {
        if type & MachOConstants.N_STAB != 0 {
            return MachOConstants.stabName(type)
        }
        var parts = [MachOConstants.symbolTypeName(type)]
        if type & MachOConstants.N_PEXT != 0 { parts.append("N_PEXT") }
        if type & MachOConstants.N_EXT != 0 { parts.append("N_EXT") }
        return parts.joined(separator: " | ")
    }

    static func symbolDescription(_ symbol: RawMachOImage.Symbol, twoLevel: Bool, dylibs: [String]) -> String {
        if symbol.type & MachOConstants.N_STAB != 0 {
            return hex(symbol.desc)
        }
        var parts: [String] = []
        let isUndefined = symbol.type & MachOConstants.N_TYPE == 0
        if isUndefined {
            parts.append(MachOConstants.referenceTypeName(symbol.desc))
        }
        let hasLibraryOrdinal = twoLevel && (isUndefined || symbol.type & MachOConstants.N_TYPE == 0xC)
        for (bit, name) in MachOConstants.symbolDescriptionFlags where symbol.desc & bit != 0 {
            // In two-level images the high byte of n_desc is the library ordinal, not flags.
            if hasLibraryOrdinal, bit >= 0x100 { continue }
            // N_WEAK_DEF shares its bit with N_REF_TO_WEAK on undefined symbols.
            parts.append(isUndefined && bit == 0x80 ? "N_REF_TO_WEAK" : name)
        }
        if hasLibraryOrdinal {
            let ordinal = Int((symbol.desc >> 8) & 0xFF)
            parts.append("Library: " + MachOConstants.libraryOrdinalName(ordinal, dylibs: dylibs))
        }
        return parts.isEmpty ? hex(symbol.desc) : parts.joined(separator: ", ")
    }

    // MARK: String table

    func stringTableNode(_ symtab: RawMachOImage.Symtab) -> BrowserNode {
        let dataRange = linkEditRange(symtab.stroff, symtab.strsize)
        let content = dataRange.map { stringPoolContent(start: $0.offset, length: $0.length) } ?? .empty
        return factory.indexedNode(
            id: id("strtab"),
            title: "String Table",
            range: dataRange,
            rowCount: content.count,
            row: content.row
        )
    }

    /// Like `cstringContent`, but keyed by the index into the pool (what `n_strx` refers to).
    func stringPoolContent(start: Int, length: Int) -> SectionContent {
        let slice = slice
        let end = start + length
        let offsets = slice.reader.stringOffsets(from: start, to: end)
        return SectionContent(count: offsets.count) { index in
            let offset = start + Int(offsets[index])
            let decoded = slice.reader.cString(at: offset, limit: end)
            let stringLength = decoded?.length ?? 0
            return BrowserDetailRow(
                key: "String #\(offsets[index]) (length: \(stringLength))",
                value: escapedDisplayString(decoded?.string ?? ""),
                dataPreview: slice.reader.hexString(at: offset, count: stringLength + 1),
                rawAddress: UInt64(offset),
                rvaAddress: slice.rva(forFileOffset: offset)
            )
        }
    }

    // MARK: Dynamic symbol table

    func dynamicSymbolTableNode(_ dysymtab: RawMachOImage.Dysymtab) -> BrowserNode {
        let slice = slice
        var children: [() -> BrowserNode] = []
        if dysymtab.nindirectsyms > 0 {
            children.append { indirectSymbolsNode(dysymtab) }
        }
        if dysymtab.nextrel > 0 {
            children.append { dysymtabRelocationsNode(title: "External Relocations", key: "extrel", offset: dysymtab.extreloff, count: dysymtab.nextrel) }
        }
        if dysymtab.nlocrel > 0 {
            children.append { dysymtabRelocationsNode(title: "Local Relocations", key: "locrel", offset: dysymtab.locreloff, count: dysymtab.nlocrel) }
        }
        if dysymtab.ntoc > 0 {
            children.append { tocNode(dysymtab) }
        }
        if dysymtab.nextrefsyms > 0 {
            children.append { externalReferencesNode(dysymtab) }
        }
        if dysymtab.nmodtab > 0 {
            children.append {
                let size = UInt32(slice.is64 ? 56 : 52) * dysymtab.nmodtab
                let dataRange = linkEditRange(dysymtab.modtaboff, size)
                let content = dataRange.map { hexDumpContent(start: $0.offset, length: $0.length) } ?? .empty
                return factory.indexedNode(id: id("dysymtab", "modtab"), title: "Module Table (\(dysymtab.nmodtab))", range: dataRange, rowCount: content.count, row: content.row)
            }
        }
        return factory.node(
            id: id("dysymtab"),
            title: "Dynamic Symbol Table",
            summaryStyle: .group,
            range: nil,
            rows: {
                var rows = RowSink(slice: slice)
                func symbolRange(_ key: String, _ first: UInt32, _ count: UInt32) {
                    var value = "\(count) from index \(first)"
                    if count > 0 {
                        let names = [slice.symbol(at: Int(first))?.name, count > 1 ? slice.symbol(at: Int(first + count - 1))?.name : nil].compactMap { $0 }
                        if names.isEmpty == false { value += " (\(names.joined(separator: " … ")))" }
                    }
                    rows.note(key, value)
                }
                symbolRange("Local Symbols", dysymtab.ilocalsym, dysymtab.nlocalsym)
                symbolRange("External Defined Symbols", dysymtab.iextdefsym, dysymtab.nextdefsym)
                symbolRange("Undefined Symbols", dysymtab.iundefsym, dysymtab.nundefsym)
                rows.nextGroup()
                rows.note("Indirect Symbols", "\(dysymtab.nindirectsyms)")
                rows.note("External Relocations", "\(dysymtab.nextrel)")
                rows.note("Local Relocations", "\(dysymtab.nlocrel)")
                rows.note("Table of Contents", "\(dysymtab.ntoc)")
                rows.note("Module Table", "\(dysymtab.nmodtab)")
                rows.note("External References", "\(dysymtab.nextrefsyms)")
                return rows.rows
            },
            children: children
        )
    }

    func indirectSymbolsNode(_ dysymtab: RawMachOImage.Dysymtab) -> BrowserNode {
        let slice = slice
        let owners = slice.sections.filter { section in
            switch MachOConstants.SectionType(rawValue: section.type) {
            case .nonLazySymbolPointers, .lazySymbolPointers, .lazyDylibSymbolPointers, .threadLocalVariablePointers, .symbolStubs:
                return true
            default:
                return false
            }
        }
        return factory.indexedNode(
            id: id("dysymtab", "indirect"),
            title: "Indirect Symbols (\(dysymtab.nindirectsyms))",
            range: linkEditRange(dysymtab.indirectsymoff, dysymtab.nindirectsyms * 4),
            rowCount: Int(dysymtab.nindirectsyms),
            row: { index in
                guard let entry = slice.indirectSymbolEntry(index) else {
                    return BrowserDetailRow(key: "Invalid Entry", value: "")
                }
                var value = slice.indirectSymbolName(entry.value)
                if let owner = owners.first(where: { section in
                    let stride = MachOConstants.SectionType(rawValue: section.type) == .symbolStubs ? UInt64(max(section.reserved2, 1)) : UInt64(slice.pointerSize)
                    let count = section.size / stride
                    return UInt64(index) >= UInt64(section.reserved1) && UInt64(index) < UInt64(section.reserved1) + count
                }) {
                    let stride = MachOConstants.SectionType(rawValue: owner.type) == .symbolStubs ? UInt64(max(owner.reserved2, 1)) : UInt64(slice.pointerSize)
                    let address = owner.addr + UInt64(index - Int(owner.reserved1)) * stride
                    value += "  (\(owner.qualifiedName) \(hex(address)))"
                }
                let key = entry.value & (MachOConstants.INDIRECT_SYMBOL_LOCAL | MachOConstants.INDIRECT_SYMBOL_ABS) != 0 ? "Indirect Symbol" : "Symbol #\(entry.value)"
                return layoutRow(slice, entry.offset, 4, key, value)
            }
        )
    }

    func dysymtabRelocationsNode(title: String, key: String, offset: UInt32, count: UInt32) -> BrowserNode {
        let slice = slice
        let relocations = slice.relocations(at: offset, count: count)
        let base = slice.externalRelocationBase
        let rowsPerEntry = 6
        return factory.indexedNode(
            id: id("dysymtab", key),
            title: "\(title) (\(relocations.count))",
            range: linkEditRange(offset, count * 8),
            rowCount: relocations.count * rowsPerEntry,
            row: { index in
                Self.relocationRow(slice, relocations[index / rowsPerEntry], field: index % rowsPerEntry, group: UInt(index / rowsPerEntry), addressBase: base)
            }
        )
    }

    func tocNode(_ dysymtab: RawMachOImage.Dysymtab) -> BrowserNode {
        let slice = slice
        return factory.indexedNode(
            id: id("dysymtab", "toc"),
            title: "Table of Contents (\(dysymtab.ntoc))",
            range: linkEditRange(dysymtab.tocoff, dysymtab.ntoc * 8),
            rowCount: Int(dysymtab.ntoc) * 2,
            row: { index in
                guard let entry = slice.absolute(UInt64(dysymtab.tocoff) + UInt64(index / 2 * 8)) else {
                    return BrowserDetailRow(key: "Invalid Entry", value: "")
                }
                if index % 2 == 0 {
                    let symbol = slice.u32(entry)
                    return layoutRow(slice, entry, 4, "Symbol Index", "\(symbol) (\(slice.symbol(at: Int(symbol))?.name ?? "?"))", group: UInt(index / 2))
                }
                return layoutRow(slice, entry + 4, 4, "Module Index", "\(slice.u32(entry + 4))", group: UInt(index / 2))
            }
        )
    }

    func externalReferencesNode(_ dysymtab: RawMachOImage.Dysymtab) -> BrowserNode {
        let slice = slice
        return factory.indexedNode(
            id: id("dysymtab", "extref"),
            title: "External References (\(dysymtab.nextrefsyms))",
            range: linkEditRange(dysymtab.extrefsymoff, dysymtab.nextrefsyms * 4),
            rowCount: Int(dysymtab.nextrefsyms),
            row: { index in
                guard let entry = slice.absolute(UInt64(dysymtab.extrefsymoff) + UInt64(index * 4)) else {
                    return BrowserDetailRow(key: "Invalid Entry", value: "")
                }
                let raw = slice.u32(entry)
                let symbolIndex = slice.swapped ? raw >> 8 : raw & 0x00FF_FFFF
                return layoutRow(slice, entry, 4, "Symbol #\(symbolIndex)", slice.symbol(at: Int(symbolIndex))?.name ?? "?")
            }
        )
    }

    // MARK: Function starts / data in code / LOH

    func functionStartsNode(_ data: RawMachOImage.LinkEditData) -> BrowserNode {
        let slice = slice
        let dataRange = linkEditRange(data.dataoff, data.datasize)
        var entries: [(offset: Int, length: Int, address: UInt64)] = []
        if let dataRange {
            let end = dataRange.offset + dataRange.length
            var cursor = dataRange.offset
            var address = slice.segments.first { $0.name == "__TEXT" }?.vmaddr ?? slice.imageBase
            while cursor < end, let decoded = slice.reader.uleb128(at: cursor, limit: end), decoded.value != 0 {
                address &+= decoded.value
                entries.append((cursor, decoded.length, address))
                cursor += decoded.length
            }
        }
        return factory.indexedNode(
            id: id("function-starts"),
            title: "Function Starts (\(entries.count))",
            range: dataRange,
            rowCount: entries.count,
            row: { index in
                let entry = entries[index]
                var value = hex(entry.address)
                if let name = slice.symbolName(forVM: entry.address) {
                    value += "  \(name)"
                }
                return BrowserDetailRow(
                    key: "Function",
                    value: value,
                    dataPreview: slice.reader.hexString(at: entry.offset, count: entry.length),
                    rawAddress: UInt64(entry.offset),
                    rvaAddress: slice.rva(forFileOffset: entry.offset)
                )
            }
        )
    }

    func dataInCodeNode(_ data: RawMachOImage.LinkEditData) -> BrowserNode {
        let slice = slice
        let dataRange = linkEditRange(data.dataoff, data.datasize)
        let count = (dataRange?.length ?? 0) / 8
        let start = dataRange?.offset ?? 0
        let textBase = slice.imageBase
        return factory.indexedNode(
            id: id("data-in-code"),
            title: "Data in Code Entries (\(count))",
            range: dataRange,
            rowCount: count * 3,
            row: { index in
                let entry = start + index / 3 * 8
                let group = UInt(index / 3)
                switch index % 3 {
                case 0:
                    let offset = slice.u32(entry)
                    return layoutRow(slice, entry, 4, "Offset", "\(hex(offset))  (\(hex(textBase &+ UInt64(offset))))", group: group)
                case 1:
                    return layoutRow(slice, entry + 4, 2, "Length", "\(slice.u16(entry + 4))", group: group)
                default:
                    return layoutRow(slice, entry + 6, 2, "Kind", MachOConstants.dataInCodeKindName(slice.u16(entry + 6)), group: group)
                }
            }
        )
    }

    static func linkerOptimizationHintName(_ kind: UInt64) -> String {
        switch kind {
        case 1: return "LOH_ARM64_ADRP_ADRP"
        case 2: return "LOH_ARM64_ADRP_LDR"
        case 3: return "LOH_ARM64_ADRP_ADD_LDR"
        case 4: return "LOH_ARM64_ADRP_LDR_GOT_LDR"
        case 5: return "LOH_ARM64_ADRP_ADD_STR"
        case 6: return "LOH_ARM64_ADRP_LDR_GOT_STR"
        case 7: return "LOH_ARM64_ADRP_ADD"
        case 8: return "LOH_ARM64_ADRP_LDR_GOT"
        default: return "LOH_UNKNOWN (\(kind))"
        }
    }

    func linkerOptimizationHintsNode(_ data: RawMachOImage.LinkEditData) -> BrowserNode {
        let slice = slice
        let dataRange = linkEditRange(data.dataoff, data.datasize)
        return factory.node(
            id: id("loh"),
            title: "Linker Optimization Hints",
            range: dataRange,
            rows: {
                guard let dataRange else { return [] }
                var rows = RowSink(slice: slice)
                let end = dataRange.offset + dataRange.length
                var cursor = dataRange.offset
                while cursor < end, rows.rows.count < 500_000 {
                    let kind = rows.uleb(cursor, limit: end, "Kind", format: { Self.linkerOptimizationHintName($0) })
                    if kind.value == 0 { break }
                    cursor += kind.length
                    let count = rows.uleb(cursor, limit: end, "Argument Count")
                    cursor += count.length
                    for _ in 0..<min(count.value, 16) {
                        let address = rows.uleb(cursor, limit: end, "Address", format: { hex($0) })
                        cursor += address.length
                    }
                    rows.nextGroup()
                }
                return rows.rows
            }
        )
    }
}

import Foundation

extension MachOLayoutBuilder {
    // MARK: LC_DYLD_INFO

    func dyldInfoNode(_ info: RawMachOImage.DyldInfo) -> BrowserNode {
        let slice = slice
        var children: [() -> BrowserNode] = []
        if info.rebaseSize > 0 {
            children.append { rebaseInfoNode(info) }
        }
        let bindStreams: [(RawMachOImage.BindAction.Kind, UInt32, UInt32, String)] = [
            (.bind, info.bindOff, info.bindSize, "Binding Info"),
            (.weak, info.weakBindOff, info.weakBindSize, "Weak Binding Info"),
            (.lazy, info.lazyBindOff, info.lazyBindSize, "Lazy Binding Info"),
        ]
        for (kind, offset, size, title) in bindStreams where size > 0 {
            children.append { bindInfoNode(kind: kind, offset: offset, size: size, title: title) }
        }
        if info.exportSize > 0 {
            children.append { exportTrieNode(id: id("dyldinfo", "export"), title: "Export Info", offset: info.exportOff, size: info.exportSize) }
        }
        return factory.node(
            id: id("dyldinfo"),
            title: "Dynamic Loader Info",
            summaryStyle: .group,
            range: nil,
            rows: {
                var rows = RowSink(slice: slice)
                rows.note("Rebase Info", "\(hex(info.rebaseOff)) size \(byteCount(UInt64(info.rebaseSize)))")
                rows.note("Binding Info", "\(hex(info.bindOff)) size \(byteCount(UInt64(info.bindSize)))")
                rows.note("Weak Binding Info", "\(hex(info.weakBindOff)) size \(byteCount(UInt64(info.weakBindSize)))")
                rows.note("Lazy Binding Info", "\(hex(info.lazyBindOff)) size \(byteCount(UInt64(info.lazyBindSize)))")
                rows.note("Export Info", "\(hex(info.exportOff)) size \(byteCount(UInt64(info.exportSize)))")
                return rows.rows
            },
            children: children
        )
    }

    func segmentLabel(_ index: Int) -> String {
        index >= 0 && index < slice.segments.count ? slice.segments[index].name : "segment #\(index)"
    }

    func rebaseInfoNode(_ info: RawMachOImage.DyldInfo) -> BrowserNode {
        let slice = slice
        let dataRange = linkEditRange(info.rebaseOff, info.rebaseSize)
        return factory.node(
            id: id("dyldinfo", "rebase"),
            title: "Rebase Info",
            range: dataRange,
            rows: {
                guard let dataRange else { return [] }
                return rebaseOpcodeRows(start: dataRange.offset, end: dataRange.offset + dataRange.length)
            },
            children: [{
                let actions = slice.rebaseActions
                return factory.indexedNode(
                    id: id("dyldinfo", "rebase", "actions"),
                    title: "Actions (\(actions.count))",
                    range: nil,
                    rowCount: actions.count,
                    row: { index in
                        let action = actions[index]
                        var value = "\(segmentLabel(action.segmentIndex))  \(MachOConstants.rebaseTypeName(action.type))"
                        if let section = slice.section(containingVM: action.address) {
                            value += "  (\(section.qualifiedName))"
                        }
                        return BrowserDetailRow(
                            key: hex(action.address),
                            value: value,
                            rawAddress: UInt64(action.opcodeOffset),
                            rvaAddress: action.address
                        )
                    }
                )
            }]
        )
    }

    func rebaseOpcodeRows(start: Int, end: Int) -> [BrowserDetailRow] {
        var rows = sink()
        var cursor = start
        while cursor < end, rows.rows.count < 1_000_000 {
            let byte = slice.u8(cursor)
            let opcode = byte & 0xF0
            let immediate = byte & 0x0F
            let name = MachOConstants.rebaseOpcodeName(opcode)
            switch opcode {
            case 0x10:
                rows.field(cursor, 1, name, "type (\(immediate)) \(MachOConstants.rebaseTypeName(immediate))")
                cursor += 1
            case 0x20:
                rows.field(cursor, 1, name, "segment (\(immediate)) \(segmentLabel(Int(immediate)))")
                cursor += 1
                cursor += rows.uleb(cursor, limit: end, "offset", format: { hex($0) }).length
            case 0x30:
                rows.field(cursor, 1, name, "")
                cursor += 1
                cursor += rows.uleb(cursor, limit: end, "offset", format: { hex($0) }).length
            case 0x40:
                rows.field(cursor, 1, name, "scale (\(immediate))")
                cursor += 1
            case 0x50:
                rows.field(cursor, 1, name, "count (\(immediate))")
                cursor += 1
            case 0x60:
                rows.field(cursor, 1, name, "")
                cursor += 1
                cursor += rows.uleb(cursor, limit: end, "count").length
            case 0x70:
                rows.field(cursor, 1, name, "")
                cursor += 1
                cursor += rows.uleb(cursor, limit: end, "offset", format: { hex($0) }).length
            case 0x80:
                rows.field(cursor, 1, name, "")
                cursor += 1
                cursor += rows.uleb(cursor, limit: end, "count").length
                cursor += rows.uleb(cursor, limit: end, "skip", format: { hex($0) }).length
            default:
                rows.field(cursor, 1, name, "")
                cursor += 1
            }
            if opcode == 0x00 { rows.nextGroup() }
        }
        return rows.rows
    }

    func bindInfoNode(kind: RawMachOImage.BindAction.Kind, offset: UInt32, size: UInt32, title: String) -> BrowserNode {
        let slice = slice
        let dataRange = linkEditRange(offset, size)
        let dylibs = slice.dylibs
        return factory.node(
            id: id("dyldinfo", kind.rawValue),
            title: title,
            range: dataRange,
            rows: {
                guard let dataRange else { return [] }
                return bindOpcodeRows(start: dataRange.offset, end: dataRange.offset + dataRange.length)
            },
            children: [{
                let actions = slice.bindActions.filter { $0.kind == kind }
                return factory.indexedNode(
                    id: id("dyldinfo", kind.rawValue, "actions"),
                    title: "Actions (\(actions.count))",
                    range: nil,
                    rowCount: actions.count,
                    row: { index in
                        let action = actions[index]
                        var value = action.symbol
                        if action.addend != 0 { value += " + \(action.addend)" }
                        value += "  [\(MachOConstants.libraryOrdinalName(action.ordinal, dylibs: dylibs))]"
                        if action.flags & 0x1 != 0 { value += " weak_import" }
                        if action.flags & 0x8 != 0 { value += " non_weak_definition" }
                        value += "  \(segmentLabel(action.segmentIndex))"
                        if let section = slice.section(containingVM: action.address) {
                            value += " (\(section.qualifiedName))"
                        }
                        return BrowserDetailRow(
                            key: hex(action.address),
                            value: value,
                            rawAddress: UInt64(action.opcodeOffset),
                            rvaAddress: action.address
                        )
                    }
                )
            }]
        )
    }

    func bindOpcodeRows(start: Int, end: Int) -> [BrowserDetailRow] {
        var rows = sink()
        var cursor = start
        let dylibs = slice.dylibs
        while cursor < end, rows.rows.count < 1_000_000 {
            let byte = slice.u8(cursor)
            let opcode = byte & 0xF0
            let immediate = byte & 0x0F
            let name = MachOConstants.bindOpcodeName(opcode)
            switch opcode {
            case 0x00:
                rows.field(cursor, 1, name, "")
                cursor += 1
                rows.nextGroup()
            case 0x10:
                rows.field(cursor, 1, name, "dylib (\(MachOConstants.libraryOrdinalName(Int(immediate), dylibs: dylibs)))")
                cursor += 1
            case 0x20:
                rows.field(cursor, 1, name, "")
                cursor += 1
                cursor += rows.uleb(cursor, limit: end, "dylib", format: { MachOConstants.libraryOrdinalName(Int($0), dylibs: dylibs) }).length
            case 0x30:
                let ordinal = immediate == 0 ? 0 : Int(Int8(bitPattern: 0xF0 | immediate))
                rows.field(cursor, 1, name, "dylib (\(MachOConstants.libraryOrdinalName(ordinal, dylibs: dylibs)))")
                cursor += 1
            case 0x40:
                var flags: [String] = []
                if immediate & 0x1 != 0 { flags.append("BIND_SYMBOL_FLAGS_WEAK_IMPORT") }
                if immediate & 0x8 != 0 { flags.append("BIND_SYMBOL_FLAGS_NON_WEAK_DEFINITION") }
                rows.field(cursor, 1, name, "flags (\(immediate))" + (flags.isEmpty ? "" : " " + flags.joined(separator: " | ")))
                cursor += 1
                if let decoded = slice.reader.cString(at: cursor, limit: end) {
                    rows.bytes(cursor, decoded.length + 1, "string", escapedDisplayString(decoded.string))
                    cursor += decoded.length + 1
                } else {
                    cursor = end
                }
            case 0x50:
                rows.field(cursor, 1, name, "type (\(immediate)) \(MachOConstants.bindTypeName(immediate))")
                cursor += 1
            case 0x60:
                rows.field(cursor, 1, name, "")
                cursor += 1
                if let decoded = slice.reader.sleb128(at: cursor, limit: end) {
                    rows.append(cursor, slice.reader.hexString(at: cursor, count: decoded.length), "sleb128", "\(decoded.value)")
                    cursor += decoded.length
                } else {
                    cursor = end
                }
            case 0x70:
                rows.field(cursor, 1, name, "segment (\(immediate)) \(segmentLabel(Int(immediate)))")
                cursor += 1
                cursor += rows.uleb(cursor, limit: end, "offset", format: { hex($0) }).length
            case 0x80:
                rows.field(cursor, 1, name, "")
                cursor += 1
                cursor += rows.uleb(cursor, limit: end, "offset", format: { hex($0) }).length
            case 0x90:
                rows.field(cursor, 1, name, "")
                cursor += 1
            case 0xA0:
                rows.field(cursor, 1, name, "")
                cursor += 1
                cursor += rows.uleb(cursor, limit: end, "offset", format: { hex($0) }).length
            case 0xB0:
                rows.field(cursor, 1, name, "scale (\(immediate))")
                cursor += 1
            case 0xC0:
                rows.field(cursor, 1, name, "")
                cursor += 1
                cursor += rows.uleb(cursor, limit: end, "count").length
                cursor += rows.uleb(cursor, limit: end, "skip", format: { hex($0) }).length
            case 0xD0:
                rows.field(cursor, 1, name, immediate == 0 ? "BIND_SUBOPCODE_THREADED_SET_BIND_ORDINAL_TABLE_SIZE_ULEB" : "BIND_SUBOPCODE_THREADED_APPLY")
                cursor += 1
                if immediate == 0 {
                    cursor += rows.uleb(cursor, limit: end, "count").length
                }
            default:
                rows.field(cursor, 1, name, "")
                cursor += 1
            }
        }
        return rows.rows
    }

    // MARK: Export trie

    struct ExportEntry {
        let name: String
        let nodeOffset: Int
        let flags: UInt64
        let address: UInt64?
        let other: UInt64?
        let importName: String?
    }

    func exportTrieNode(id nodeID: String, title: String, offset: UInt32, size: UInt32) -> BrowserNode {
        let slice = slice
        let dataRange = linkEditRange(offset, size)
        return factory.node(
            id: nodeID,
            title: title,
            range: dataRange,
            rows: {
                guard let dataRange else { return [] }
                return exportTrieRows(start: dataRange.offset, end: dataRange.offset + dataRange.length)
            },
            children: [{
                let exports = dataRange.map { exportEntries(start: $0.offset, end: $0.offset + $0.length) } ?? []
                let base = slice.imageBase
                return factory.indexedNode(
                    id: nodeID + "/symbols",
                    title: "Exported Symbols (\(exports.count))",
                    range: nil,
                    rowCount: exports.count,
                    row: { index in
                        let entry = exports[index]
                        var value: String
                        if entry.flags & 0x08 != 0 {
                            let ordinal = Int(entry.other ?? 0)
                            value = "re-export from \(MachOConstants.libraryOrdinalName(ordinal, dylibs: slice.dylibs))"
                            if let importName = entry.importName, importName.isEmpty == false {
                                value += " as \(importName)"
                            }
                        } else {
                            let address = entry.flags & 0x3 == 2 ? (entry.address ?? 0) : base &+ (entry.address ?? 0)
                            value = hex(address)
                            if entry.flags & 0x10 != 0, let other = entry.other {
                                value += "  resolver \(hex(base &+ other))"
                            }
                        }
                        if entry.flags & 0x04 != 0 { value += "  [weak]" }
                        if entry.flags & 0x3 == 1 { value += "  [thread-local]" }
                        return BrowserDetailRow(
                            key: entry.name,
                            value: value,
                            rawAddress: UInt64(entry.nodeOffset),
                            rvaAddress: entry.address.map { entry.flags & 0x3 == 2 ? $0 : base &+ $0 }
                        )
                    }
                )
            }]
        )
    }

    func exportEntries(start: Int, end: Int) -> [ExportEntry] {
        var result: [ExportEntry] = []
        var stack: [(offset: Int, prefix: String)] = [(start, "")]
        var visited = Set<Int>()
        let reader = slice.reader
        while let (node, prefix) = stack.popLast() {
            guard node < end, visited.insert(node).inserted else { continue }
            guard let terminal = reader.uleb128(at: node, limit: end) else { continue }
            var cursor = node + terminal.length
            if terminal.value > 0 {
                var info = cursor
                if let flags = reader.uleb128(at: info, limit: end) {
                    info += flags.length
                    if flags.value & 0x08 != 0 {
                        let ordinal = reader.uleb128(at: info, limit: end)
                        info += ordinal?.length ?? 0
                        let importName = reader.cString(at: info, limit: end)?.string
                        result.append(ExportEntry(name: prefix, nodeOffset: node, flags: flags.value, address: nil, other: ordinal?.value, importName: importName))
                    } else {
                        let address = reader.uleb128(at: info, limit: end)
                        info += address?.length ?? 0
                        let other = flags.value & 0x10 != 0 ? reader.uleb128(at: info, limit: end)?.value : nil
                        result.append(ExportEntry(name: prefix, nodeOffset: node, flags: flags.value, address: address?.value, other: other, importName: nil))
                    }
                }
            }
            cursor += Int(terminal.value)
            guard cursor < end else { continue }
            let childCount = Int(slice.u8(cursor))
            cursor += 1
            var children: [(Int, String)] = []
            for _ in 0..<childCount {
                guard let label = reader.cString(at: cursor, limit: end) else { break }
                cursor += label.length + 1
                guard let childOffset = reader.uleb128(at: cursor, limit: end) else { break }
                cursor += childOffset.length
                children.append((start + Int(childOffset.value), prefix + label.string))
            }
            stack.append(contentsOf: children.reversed())
        }
        return result.sorted { $0.name < $1.name }
    }

    func exportTrieRows(start: Int, end: Int) -> [BrowserDetailRow] {
        var rows = sink()
        var queue: [(offset: Int, prefix: String)] = [(start, "")]
        var visited = Set<Int>()
        var nodes: [(Int, String)] = []
        // Collect nodes first so rows follow file order, as MachOView prints them.
        while let (node, prefix) = queue.popLast() {
            guard node < end, visited.insert(node).inserted else { continue }
            nodes.append((node, prefix))
            guard let terminal = slice.reader.uleb128(at: node, limit: end) else { continue }
            var cursor = node + terminal.length + Int(terminal.value)
            guard cursor < end else { continue }
            let childCount = Int(slice.u8(cursor))
            cursor += 1
            for _ in 0..<childCount {
                guard let label = slice.reader.cString(at: cursor, limit: end) else { break }
                cursor += label.length + 1
                guard let childOffset = slice.reader.uleb128(at: cursor, limit: end) else { break }
                cursor += childOffset.length
                queue.append((start + Int(childOffset.value), prefix + label.string))
            }
        }
        for (node, prefix) in nodes.sorted(by: { $0.0 < $1.0 }) where rows.rows.count < 1_000_000 {
            guard let terminal = slice.reader.uleb128(at: node, limit: end) else { continue }
            var cursor = node
            cursor += rows.uleb(cursor, limit: end, "Terminal Size").length
            if terminal.value > 0 {
                rows.note("Symbol", prefix)
                let flags = rows.uleb(cursor, limit: end, "Flags", format: { hex($0) })
                rows.note("", MachOConstants.exportKindName(flags.value))
                rows.flags(flags.value, MachOConstants.exportSymbolFlags, width: 1)
                cursor += flags.length
                if flags.value & 0x08 != 0 {
                    cursor += rows.uleb(cursor, limit: end, "Library Ordinal", format: { MachOConstants.libraryOrdinalName(Int($0), dylibs: slice.dylibs) }).length
                    if let name = slice.reader.cString(at: cursor, limit: end) {
                        rows.bytes(cursor, name.length + 1, "Import Name", name.string)
                    }
                } else {
                    cursor += rows.uleb(cursor, limit: end, "Symbol Offset", format: { hex($0) }).length
                    if flags.value & 0x10 != 0 {
                        rows.uleb(cursor, limit: end, "Resolver Offset", format: { hex($0) })
                    }
                }
                cursor = node + terminal.length + Int(terminal.value)
            }
            guard cursor < end else { continue }
            let childCount = rows.u8(cursor, "Child Count")
            cursor += 1
            for _ in 0..<childCount {
                guard let label = slice.reader.cString(at: cursor, limit: end) else { break }
                rows.bytes(cursor, label.length + 1, "Node Label", label.string)
                cursor += label.length + 1
                let next = rows.uleb(cursor, limit: end, "Next Node", format: { hex(UInt64(start) &+ $0) })
                cursor += next.length
            }
            rows.nextGroup()
        }
        return rows.rows
    }

    // MARK: Chained fixups

    func chainedFixupsNode(_ data: RawMachOImage.LinkEditData) -> BrowserNode {
        let slice = slice
        let dataRange = linkEditRange(data.dataoff, data.datasize)
        guard let fixups = slice.chainedFixups else {
            return rawLinkEditNode(data)
        }
        var children: [() -> BrowserNode] = [
            { chainedStartsNode(fixups) },
        ]
        for starts in fixups.segments {
            children.append { chainedSegmentStartsNode(fixups, starts) }
        }
        children.append { chainedImportsNode(fixups) }
        children.append {
            let length = fixups.end - fixups.symbolsOffset
            let content = length > 0 ? stringPoolContent(start: fixups.symbolsOffset, length: length) : .empty
            return factory.indexedNode(id: id("chained", "symbols"), title: "Symbols", range: range(fixups.symbolsOffset, length), rowCount: content.count, row: content.row)
        }
        children.append { chainedFixupListNode(fixups) }
        return factory.node(
            id: id("chained"),
            title: "Chained Fixups",
            range: dataRange,
            rows: {
                var rows = RowSink(slice: slice)
                let header = fixups.headerOffset
                rows.u32(header, "Fixups Version")
                rows.u32(header + 4, "Starts Offset", format: { hex($0) })
                rows.u32(header + 8, "Imports Offset", format: { hex($0) })
                rows.u32(header + 12, "Symbols Offset", format: { hex($0) })
                rows.u32(header + 16, "Imports Count")
                rows.u32(header + 20, "Imports Format", format: { MachOConstants.chainedImportFormatName($0) })
                rows.u32(header + 24, "Symbols Format", format: { MachOConstants.chainedSymbolsFormatName($0) })
                return rows.rows
            },
            children: children
        )
    }

    func chainedStartsNode(_ fixups: RawMachOImage.ChainedFixups) -> BrowserNode {
        let slice = slice
        let segmentCount = Int(slice.u32(fixups.startsOffset))
        return factory.node(
            id: id("chained", "starts"),
            title: "Starts in Image",
            range: range(fixups.startsOffset, 4 + segmentCount * 4),
            rows: {
                var rows = RowSink(slice: slice)
                rows.u32(fixups.startsOffset, "Segment Count")
                for index in 0..<min(segmentCount, 256) {
                    let name = index < slice.segments.count ? slice.segments[index].name : "#\(index)"
                    rows.u32(fixups.startsOffset + 4 + index * 4, "Segment Info Offset (\(name))", format: { $0 == 0 ? "0 (no fixups)" : hex($0) })
                }
                return rows.rows
            }
        )
    }

    func chainedSegmentStartsNode(_ fixups: RawMachOImage.ChainedFixups, _ starts: RawMachOImage.ChainedSegmentStarts) -> BrowserNode {
        let slice = slice
        let name = starts.segmentIndex < slice.segments.count ? slice.segments[starts.segmentIndex].name : "#\(starts.segmentIndex)"
        return factory.node(
            id: id("chained", "segment", "\(starts.segmentIndex)"),
            title: "Segment Starts (\(name))",
            range: range(starts.offset, Int(max(starts.size, 22))),
            rows: {
                var rows = RowSink(slice: slice)
                rows.u32(starts.offset, "Size")
                rows.u16(starts.offset + 4, "Page Size", format: { hex($0) })
                rows.u16(starts.offset + 6, "Pointer Format", format: { MachOConstants.chainedPointerFormatName($0) })
                rows.u64(starts.offset + 8, "Segment Offset", format: { hex($0) })
                rows.u32(starts.offset + 16, "Max Valid Pointer", format: { hex($0) })
                rows.u16(starts.offset + 20, "Page Count")
                for page in 0..<Int(starts.pageCount) {
                    rows.u16(starts.pageStartsOffset + page * 2, "Page Start [\(page)]") { value in
                        if value == 0xFFFF { return "DYLD_CHAINED_PTR_START_NONE" }
                        if value & 0x8000 != 0, [3, 4, 5].contains(starts.pointerFormat) { return "DYLD_CHAINED_PTR_START_MULTI \(hex(value & 0x7FFF))" }
                        return hex(value)
                    }
                }
                return rows.rows
            }
        )
    }

    func chainedImportsNode(_ fixups: RawMachOImage.ChainedFixups) -> BrowserNode {
        let slice = slice
        let entrySize = fixups.importsFormat == 3 ? 16 : (fixups.importsFormat == 2 ? 8 : 4)
        let imports = fixups.imports
        let first = imports.first?.offset ?? fixups.headerOffset
        return factory.indexedNode(
            id: id("chained", "imports"),
            title: "Imports (\(imports.count))",
            range: imports.isEmpty ? nil : range(first, imports.count * entrySize),
            rowCount: imports.count,
            row: { index in
                let item = imports[index]
                var value = "\(MachOConstants.libraryOrdinalName(item.libraryOrdinal, dylibs: slice.dylibs))"
                if item.weak { value += "  weak" }
                if item.addend != 0 { value += "  addend \(item.addend)" }
                return BrowserDetailRow(
                    key: "[\(index)] \(item.name)",
                    value: value,
                    dataPreview: slice.reader.hexString(at: item.offset, count: entrySize),
                    rawAddress: UInt64(item.offset),
                    rvaAddress: slice.rva(forFileOffset: item.offset)
                )
            }
        )
    }

    func chainedFixupListNode(_ fixups: RawMachOImage.ChainedFixups) -> BrowserNode {
        let slice = slice
        let list = fixups.fixups
        return factory.indexedNode(
            id: id("chained", "fixups"),
            title: "Fixups (\(list.count))",
            range: nil,
            rowCount: list.count,
            row: { index in
                let fixup = list[index]
                let key: String
                var value: String
                switch fixup.kind {
                case let .rebase(target):
                    key = "Rebase"
                    value = slice.describe(.address(target))
                case let .bind(ordinal, addend):
                    key = "Bind"
                    value = "[\(ordinal)] \(slice.chainedImportName(ordinal))"
                    if addend != 0 { value += " + \(addend)" }
                }
                if let auth = fixup.auth {
                    let keyName = ["IA", "IB", "DA", "DB"][Int(auth.key & 3)]
                    value += "  auth(key \(keyName), diversity \(hex(auth.diversity))\(auth.addressDiversity ? ", addr" : ""))"
                }
                value += "  next \(fixup.next)"
                let size = fixup.format == 3 ? 4 : 8
                return BrowserDetailRow(
                    key: key,
                    value: value,
                    dataPreview: padded(fixup.raw, width: size),
                    rawAddress: UInt64(fixup.offset),
                    rvaAddress: slice.rva(forFileOffset: fixup.offset)
                )
            }
        )
    }
}

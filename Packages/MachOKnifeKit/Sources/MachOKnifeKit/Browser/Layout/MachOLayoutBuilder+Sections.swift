import Foundation

/// One detail row anchored at an absolute file offset.
func layoutRow(
    _ slice: RawMachOImage,
    _ offset: Int,
    _ size: Int,
    _ key: String,
    _ value: String,
    integer: Bool = true,
    group: UInt = 0
) -> BrowserDetailRow {
    let data: String?
    if integer, let value = slice.reader.unsigned(at: offset, size: size, swapped: slice.swapped) {
        data = padded(value, width: size)
    } else {
        data = slice.reader.hexString(at: offset, count: size, maximumBytes: 32)
    }
    return BrowserDetailRow(
        key: key,
        value: value,
        dataPreview: data,
        rawAddress: UInt64(offset),
        rvaAddress: slice.rva(forFileOffset: offset),
        groupIdentifier: group
    )
}

func escapedDisplayString(_ string: String) -> String {
    var result = ""
    result.reserveCapacity(string.count)
    for scalar in string.unicodeScalars {
        switch scalar {
        case "\n": result += "\\n"
        case "\r": result += "\\r"
        case "\t": result += "\\t"
        default:
            if scalar.value < 0x20 {
                result += String(format: "\\x%02X", scalar.value)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
    }
    return result
}

func asciiPreview(_ bytes: Data) -> String {
    String(bytes.map { $0 >= 0x20 && $0 < 0x7F ? Character(UnicodeScalar($0)) : "." })
}

/// Lazily evaluated rows and children of a section node.
struct SectionContent {
    var count: Int
    var row: (Int) -> BrowserDetailRow
    var children: [() -> BrowserNode] = []

    static var empty: SectionContent { SectionContent(count: 0, row: { _ in BrowserDetailRow(key: "", value: "") }) }
}

extension MachOLayoutBuilder {
    func sectionTitle(_ section: RawMachOImage.Section) -> String {
        "\(slice.is64 ? "Section64" : "Section") (\(section.segmentName),\(section.name))"
    }

    func sectionNode(_ section: RawMachOImage.Section) -> BrowserNode {
        let start = section.isZerofill ? nil : slice.absolute(UInt64(section.offset))
        let dataRange = start.flatMap { range($0, Int(clamping: section.size)) }
        var content: SectionContent
        if let dataRange {
            content = sectionContent(section, start: dataRange.offset, length: dataRange.length)
        } else {
            let rows = [
                BrowserDetailRow(key: "Zero Fill", value: section.isZerofill ? "Yes" : "No data in file"),
                BrowserDetailRow(key: "Address", value: hex(section.addr)),
                BrowserDetailRow(key: "Size", value: byteCount(section.size)),
            ]
            content = SectionContent(count: rows.count, row: { rows[$0] })
        }
        if section.nreloc > 0 {
            content.children.append { relocationsNode(section) }
        }
        let children = content.children
        return factory.indexedNode(
            id: id("section", "\(section.ordinal)"),
            title: sectionTitle(section),
            subtitle: MachOConstants.sectionTypeName(section.type),
            range: dataRange,
            rvaAddress: section.addr,
            rowCount: content.count,
            row: content.row,
            childCount: children.count,
            child: { children[$0]() }
        )
    }

    // MARK: Content dispatch

    func sectionContent(_ section: RawMachOImage.Section, start: Int, length: Int) -> SectionContent {
        let p = slice.pointerSize
        switch section.name {
        case "__objc_classlist", "__objc_nlclslist":
            return objcClassListContent(section, start: start, length: length)
        case "__objc_catlist", "__objc_nlcatlist", "__objc_catlist2":
            return objcCategoryListContent(section, start: start, length: length)
        case "__objc_protolist":
            return objcProtocolListContent(section, start: start, length: length)
        case "__objc_selrefs":
            return pointerContent(start: start, length: length, key: "Selector Reference") { slice, pointer in
                ObjCLayout(slice: slice).string(pointer) ?? slice.describe(pointer)
            }
        case "__objc_classrefs":
            return pointerContent(start: start, length: length, key: "Class Reference") { slice, pointer in
                ObjCLayout(slice: slice).className(pointer)
            }
        case "__objc_superrefs":
            return pointerContent(start: start, length: length, key: "Super Class Reference") { slice, pointer in
                ObjCLayout(slice: slice).className(pointer)
            }
        case "__objc_protorefs":
            return pointerContent(start: start, length: length, key: "Protocol Reference") { slice, pointer in
                ObjCLayout(slice: slice).protocolName(pointer)
            }
        case "__objc_imageinfo":
            return objcImageInfoContent(start: start, length: length)
        case "__cfstring":
            return cfstringContent(start: start, length: length)
        case "__ustring":
            return ustringContent(start: start, length: length)
        case "__swift5_types", "__swift5_protos", "__swift5_proto", "__swift5_entry":
            return relativePointerContent(start: start, length: length, maskLowBits: section.name == "__swift5_types")
        case "__auth_ptr":
            return pointerContent(start: start, length: length, key: "Pointer") { slice, pointer in slice.describe(pointer) }
        default:
            break
        }

        switch MachOConstants.SectionType(rawValue: section.type) {
        case .cstringLiterals:
            return cstringContent(start: start, length: length)
        case .fourByteLiterals:
            return literalContent(start: start, length: length, width: 4, key: "Float Literal") { slice, offset in
                "\(Float(bitPattern: slice.u32(offset)))"
            }
        case .eightByteLiterals:
            return literalContent(start: start, length: length, width: 8, key: "Double Literal") { slice, offset in
                "\(Double(bitPattern: slice.u64(offset)))"
            }
        case .sixteenByteLiterals:
            return literalContent(start: start, length: length, width: 16, key: "16-Byte Literal", integer: false) { slice, offset in
                slice.reader.hexString(at: offset, count: 16)
            }
        case .literalPointers:
            return pointerContent(start: start, length: length, key: "Literal Pointer") { slice, pointer in
                if let text = ObjCLayout(slice: slice).string(pointer) {
                    return escapedDisplayString(text)
                }
                return slice.describe(pointer)
            }
        case .nonLazySymbolPointers, .lazySymbolPointers, .lazyDylibSymbolPointers, .threadLocalVariablePointers:
            return indirectPointerContent(section, start: start, length: length)
        case .symbolStubs:
            if section.reserved2 > 0 {
                return stubContent(section, start: start, length: length)
            }
        case .modInitFuncPointers:
            return pointerContent(start: start, length: length, key: "Initializer") { slice, pointer in slice.describe(pointer) }
        case .modTermFuncPointers:
            return pointerContent(start: start, length: length, key: "Terminator") { slice, pointer in slice.describe(pointer) }
        case .initFuncOffsets:
            return literalContent(start: start, length: length, width: 4, key: "Initializer Offset") { slice, offset in
                slice.describe(.address(slice.imageBase &+ UInt64(slice.u32(offset))))
            }
        case .threadLocalVariables:
            return structContent(start: start, length: length, fields: [(p, "Thunk"), (p, "Key"), (p, "Offset")], pointerFields: [0, 1])
        case .interposing:
            return structContent(start: start, length: length, fields: [(p, "Replacement"), (p, "Replacee")], pointerFields: [0, 1])
        default:
            break
        }
        return hexDumpContent(start: start, length: length)
    }

    // MARK: Generic content

    func hexDumpContent(start: Int, length: Int) -> SectionContent {
        let slice = slice
        let count = (length + 15) / 16
        return SectionContent(count: count) { index in
            let offset = start + index * 16
            let size = min(16, start + length - offset)
            let bytes = slice.reader.bytes(at: offset, count: size) ?? Data()
            return BrowserDetailRow(
                key: asciiPreview(bytes),
                value: "",
                dataPreview: bytes.map { String(format: "%02X", $0) }.joined(),
                rawAddress: UInt64(offset),
                rvaAddress: slice.rva(forFileOffset: offset)
            )
        }
    }

    func cstringContent(start: Int, length: Int) -> SectionContent {
        let slice = slice
        let end = start + length
        let offsets = slice.reader.stringOffsets(from: start, to: end)
        return SectionContent(count: offsets.count) { index in
            let offset = start + Int(offsets[index])
            let decoded = slice.reader.cString(at: offset, limit: end)
            let stringLength = decoded?.length ?? 0
            return BrowserDetailRow(
                key: "CString (length: \(stringLength))",
                value: escapedDisplayString(decoded?.string ?? ""),
                dataPreview: slice.reader.hexString(at: offset, count: stringLength + 1),
                rawAddress: UInt64(offset),
                rvaAddress: slice.rva(forFileOffset: offset)
            )
        }
    }

    func ustringContent(start: Int, length: Int) -> SectionContent {
        let slice = slice
        let end = start + length
        var offsets: [Int] = []
        var cursor = start
        while cursor + 2 <= end {
            offsets.append(cursor)
            while cursor + 2 <= end, slice.u16(cursor) != 0 { cursor += 2 }
            cursor += 2
        }
        return SectionContent(count: offsets.count) { index in
            let offset = offsets[index]
            var units: [UInt16] = []
            var cursor = offset
            while cursor + 2 <= end, slice.u16(cursor) != 0 {
                units.append(slice.u16(cursor))
                cursor += 2
            }
            return BrowserDetailRow(
                key: "UString (length: \(units.count))",
                value: escapedDisplayString(String(decoding: units, as: UTF16.self)),
                dataPreview: slice.reader.hexString(at: offset, count: units.count * 2 + 2),
                rawAddress: UInt64(offset),
                rvaAddress: slice.rva(forFileOffset: offset)
            )
        }
    }

    func literalContent(
        start: Int,
        length: Int,
        width: Int,
        key: String,
        integer: Bool = true,
        value: @escaping (RawMachOImage, Int) -> String
    ) -> SectionContent {
        let slice = slice
        return SectionContent(count: length / width) { index in
            let offset = start + index * width
            return layoutRow(slice, offset, width, key, value(slice, offset), integer: integer)
        }
    }

    func pointerContent(
        start: Int,
        length: Int,
        key: String,
        value: @escaping (RawMachOImage, ResolvedPointer) -> String
    ) -> SectionContent {
        let slice = slice
        let p = slice.pointerSize
        return SectionContent(count: length / p) { index in
            let offset = start + index * p
            return layoutRow(slice, offset, p, key, value(slice, slice.resolvePointer(at: offset)))
        }
    }

    func relativePointerContent(start: Int, length: Int, maskLowBits: Bool) -> SectionContent {
        let slice = slice
        return SectionContent(count: length / 4) { index in
            let offset = start + index * 4
            var relative = Int64(slice.i32(offset))
            if maskLowBits { relative &= ~3 }
            let value = slice.rva(forFileOffset: offset).map { fieldVM in
                slice.describe(.address(UInt64(bitPattern: Int64(bitPattern: fieldVM) &+ relative)))
            } ?? "\(relative)"
            return layoutRow(slice, offset, 4, "Relative Pointer", value)
        }
    }

    /// Fixed-size records, one row per field, separated per record.
    func structContent(start: Int, length: Int, fields: [(size: Int, key: String)], pointerFields: Set<Int>) -> SectionContent {
        let slice = slice
        let stride = fields.reduce(0) { $0 + $1.size }
        let fieldOffsets = fields.indices.map { index in fields[..<index].reduce(0) { $0 + $1.size } }
        let records = stride > 0 ? length / stride : 0
        return SectionContent(count: records * fields.count) { index in
            let record = index / fields.count
            let field = index % fields.count
            let offset = start + record * stride + fieldOffsets[field]
            let size = fields[field].size
            let value: String
            if pointerFields.contains(field) {
                value = slice.describe(slice.resolvePointer(at: offset))
            } else {
                value = hex(slice.reader.unsigned(at: offset, size: size, swapped: slice.swapped) ?? 0)
            }
            return layoutRow(slice, offset, size, fields[field].key, value, group: UInt(record))
        }
    }

    // MARK: Indirect symbols

    func indirectPointerContent(_ section: RawMachOImage.Section, start: Int, length: Int) -> SectionContent {
        let slice = slice
        let p = slice.pointerSize
        return SectionContent(count: length / p) { index in
            let offset = start + index * p
            let pointer = slice.resolvePointer(at: offset)
            var name: String?
            if let entry = slice.indirectSymbolEntry(Int(section.reserved1) + index) {
                name = slice.indirectSymbolName(entry.value)
            }
            if case let .bind(boundName, _) = pointer, name == nil || name == "?" {
                name = boundName
            }
            var value = name ?? slice.describe(pointer)
            if case let .address(target) = pointer {
                value += "  → \(hex(target))"
            }
            return layoutRow(slice, offset, p, "Indirect Pointer", value)
        }
    }

    func stubContent(_ section: RawMachOImage.Section, start: Int, length: Int) -> SectionContent {
        let slice = slice
        let stubSize = Int(section.reserved2)
        return SectionContent(count: length / stubSize) { index in
            let offset = start + index * stubSize
            let name = slice.indirectSymbolEntry(Int(section.reserved1) + index).map { slice.indirectSymbolName($0.value) } ?? "?"
            return layoutRow(slice, offset, stubSize, "Symbol Stub", name, integer: false)
        }
    }

    // MARK: CFString / image info

    func cfstringContent(start: Int, length: Int) -> SectionContent {
        let slice = slice
        let p = slice.pointerSize
        let stride = 4 * p
        return SectionContent(count: (length / stride) * 4) { index in
            let record = index / 4
            let base = start + record * stride
            let group = UInt(record)
            switch index % 4 {
            case 0:
                return layoutRow(slice, base, p, "CFString ISA", slice.describe(slice.resolvePointer(at: base)), group: group)
            case 1:
                let flags = slice.u32(base + p)
                return layoutRow(slice, base + p, 4, "Flags", hex(flags), group: group)
            case 2:
                let pointer = slice.resolvePointer(at: base + 2 * p)
                let flags = slice.u32(base + p)
                let length = Int(slice.pointer(base + 3 * p))
                var text: String?
                if let target = pointer.address.flatMap({ slice.fileOffset(forVM: $0) }) {
                    // 0x7D0 marks UTF-16 contents stored in __ustring; 0x7C8 is 8-bit.
                    if flags == 0x7D0 {
                        let units = (0..<min(length, 1 << 20)).map { slice.u16(target + $0 * 2) }
                        text = String(decoding: units, as: UTF16.self)
                    } else {
                        text = slice.reader.cString(at: target, limit: slice.limit)?.string
                    }
                }
                return layoutRow(slice, base + 2 * p, p, "String", text.map(escapedDisplayString) ?? slice.describe(pointer), group: group)
            default:
                return layoutRow(slice, base + 3 * p, p, "Length", "\(slice.pointer(base + 3 * p))", group: group)
            }
        }
    }

    func objcImageInfoContent(start: Int, length: Int) -> SectionContent {
        guard length >= 8 else { return hexDumpContent(start: start, length: length) }
        var rows = sink()
        rows.u32(start, "Version")
        let flags = rows.u32(start + 4, "Flags", format: { hex($0) })
        rows.flags(flags & 0xFF, ObjCLayout.imageInfoFlags)
        let swiftABI = (flags >> 8) & 0xFF
        if swiftABI != 0 {
            rows.note("Swift ABI Version", "\(swiftABI)")
        }
        let swiftVersion = flags >> 16
        if swiftVersion != 0 {
            rows.note("Swift Language Version", "\(swiftVersion >> 8).\(swiftVersion & 0xFF)")
        }
        let built = rows.rows
        return SectionContent(count: built.count) { built[$0] }
    }

    // MARK: Objective-C lists

    func objcClassListContent(_ section: RawMachOImage.Section, start: Int, length: Int) -> SectionContent {
        let slice = slice
        let p = slice.pointerSize
        let count = length / p
        let objc = ObjCLayout(slice: slice)
        var content = SectionContent(count: count) { index in
            let offset = start + index * p
            return layoutRow(slice, offset, p, "Objective-C Class", objc.className(slice.resolvePointer(at: offset)))
        }
        content.children = (0..<count).map { index in
            { objcClassNode(section: section, entry: start + index * p, index: index) }
        }
        return content
    }

    func objcClassNode(section: RawMachOImage.Section, entry: Int, index: Int) -> BrowserNode {
        let objc = ObjCLayout(slice: slice)
        let pointer = slice.resolvePointer(at: entry)
        let name = objc.className(pointer)
        guard let classOffset = objc.offset(pointer) else {
            return factory.node(id: id("section", "\(section.ordinal)", "class", "\(index)"), title: name, range: nil, rows: {
                [BrowserDetailRow(key: "Class", value: slice.describe(pointer))]
            })
        }
        let slice = slice
        let metaOffset = objc.offset(slice.resolvePointer(at: classOffset))
        var children: [() -> BrowserNode] = []
        if let metaOffset, metaOffset != classOffset {
            children.append {
                factory.node(
                    id: id("section", "\(section.ordinal)", "class", "\(index)", "meta"),
                    title: "Meta Class (\(name))",
                    range: range(metaOffset, 5 * slice.pointerSize),
                    rows: {
                        var rows = RowSink(slice: slice)
                        objc.classRows(&rows, classOffset: metaOffset)
                        return rows.rows
                    }
                )
            }
        }
        return factory.node(
            id: id("section", "\(section.ordinal)", "class", "\(index)"),
            title: name,
            subtitle: "Objective-C Class",
            range: range(classOffset, 5 * slice.pointerSize),
            rows: {
                var rows = RowSink(slice: slice)
                objc.classRows(&rows, classOffset: classOffset)
                return rows.rows
            },
            children: children
        )
    }

    func objcCategoryListContent(_ section: RawMachOImage.Section, start: Int, length: Int) -> SectionContent {
        let slice = slice
        let p = slice.pointerSize
        let count = length / p
        let objc = ObjCLayout(slice: slice)
        func label(_ entry: Int) -> String {
            let pointer = slice.resolvePointer(at: entry)
            guard let offset = objc.offset(pointer) else { return slice.describe(pointer) }
            let names = objc.categoryNames(categoryOffset: offset)
            return "\(names.cls)(\(names.category))"
        }
        var content = SectionContent(count: count) { index in
            let offset = start + index * p
            return layoutRow(slice, offset, p, "Objective-C Category", label(offset))
        }
        content.children = (0..<count).map { index in
            {
                let entry = start + index * p
                let categoryOffset = objc.offset(slice.resolvePointer(at: entry))
                return factory.node(
                    id: id("section", "\(section.ordinal)", "category", "\(index)"),
                    title: label(entry),
                    subtitle: "Objective-C Category",
                    range: categoryOffset.flatMap { range($0, 6 * p) },
                    rows: {
                        guard let categoryOffset else {
                            return [BrowserDetailRow(key: "Category", value: slice.describe(slice.resolvePointer(at: entry)))]
                        }
                        var rows = RowSink(slice: slice)
                        objc.categoryRows(&rows, categoryOffset)
                        return rows.rows
                    }
                )
            }
        }
        return content
    }

    func objcProtocolListContent(_ section: RawMachOImage.Section, start: Int, length: Int) -> SectionContent {
        let slice = slice
        let p = slice.pointerSize
        let count = length / p
        let objc = ObjCLayout(slice: slice)
        var content = SectionContent(count: count) { index in
            let offset = start + index * p
            return layoutRow(slice, offset, p, "Objective-C Protocol", objc.protocolName(slice.resolvePointer(at: offset)))
        }
        content.children = (0..<count).map { index in
            {
                let entry = start + index * p
                let pointer = slice.resolvePointer(at: entry)
                let protocolOffset = objc.offset(pointer)
                return factory.node(
                    id: id("section", "\(section.ordinal)", "protocol", "\(index)"),
                    title: objc.protocolName(pointer),
                    subtitle: "Objective-C Protocol",
                    range: protocolOffset.flatMap { range($0, 8 * p + 8) },
                    rows: {
                        guard let protocolOffset else {
                            return [BrowserDetailRow(key: "Protocol", value: slice.describe(pointer))]
                        }
                        var rows = RowSink(slice: slice)
                        objc.protocolRows(&rows, protocolOffset)
                        return rows.rows
                    }
                )
            }
        }
        return content
    }

    // MARK: Relocations

    func relocationsNode(_ section: RawMachOImage.Section) -> BrowserNode {
        let slice = slice
        let relocations = slice.relocations(at: section.reloff, count: section.nreloc)
        let rowsPerEntry = 6
        return factory.indexedNode(
            id: id("section", "\(section.ordinal)", "relocations"),
            title: "Relocations (\(relocations.count))",
            range: linkEditRange(section.reloff, section.nreloc * 8),
            rowCount: relocations.count * rowsPerEntry,
            row: { index in
                Self.relocationRow(slice, relocations[index / rowsPerEntry], field: index % rowsPerEntry, group: UInt(index / rowsPerEntry), addressBase: section.addr)
            }
        )
    }

    static func relocationRow(
        _ slice: RawMachOImage,
        _ relocation: RawMachOImage.Relocation,
        field: Int,
        group: UInt,
        addressBase: UInt64
    ) -> BrowserDetailRow {
        let entry = relocation.offset
        func note(_ key: String, _ value: String) -> BrowserDetailRow {
            BrowserDetailRow(key: key, value: value, groupIdentifier: group)
        }
        switch field {
        case 0:
            let address = UInt64(UInt32(bitPattern: relocation.address))
            let target = addressBase &+ address
            var value = "\(hex(address))  (\(hex(target)))"
            if let name = slice.symbolName(forVM: target) {
                value += " \(name)"
            }
            return layoutRow(slice, entry, 4, relocation.isScattered ? "Scattered Address" : "Address", value, group: group)
        case 1:
            if relocation.isScattered {
                return layoutRow(slice, entry + 4, 4, "Value", slice.describe(.address(UInt64(relocation.scatteredValue))), group: group)
            }
            let value: String
            if relocation.isExtern {
                value = "Symbol #\(relocation.symbolNum): \(slice.symbol(at: Int(relocation.symbolNum))?.name ?? "?")"
            } else if relocation.symbolNum == 0 {
                value = "R_ABS"
            } else {
                value = "Section #\(relocation.symbolNum): \(slice.section(ordinal: Int(relocation.symbolNum))?.qualifiedName ?? "?")"
            }
            return layoutRow(slice, entry + 4, 4, relocation.isExtern ? "Symbol" : "Section", value, group: group)
        case 2:
            return note("PC Relative", relocation.pcRelative ? "True" : "False")
        case 3:
            return note("Length", "\(relocation.length) (\(1 << relocation.length) bytes)")
        case 4:
            return note("Extern", relocation.isExtern ? "True" : "False")
        default:
            return note("Type", MachOConstants.relocationTypeName(cpuType: slice.cputype, type: relocation.type))
        }
    }
}

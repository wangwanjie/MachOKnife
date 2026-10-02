import Foundation

/// Builds MachOView-style documents for thin Mach-O files, universal binaries and static archives
/// straight from the file bytes, so every offset matches the original file.
struct MachOLayoutDocument {
    let url: URL
    let reader: MachOByteReader
    let hexSource: BrowserHexSource
    let factory: LayoutNodeFactory

    init(url: URL) throws {
        self.url = url
        self.reader = try MachOByteReader(url: url)
        self.hexSource = .file(url: url, size: reader.size)
        self.factory = LayoutNodeFactory(hexSource: hexSource, rva: { _ in nil })
    }

    /// Returns `nil` when the file is not a Mach-O, universal or archive container.
    static func load(url: URL) throws -> BrowserDocument? {
        try MachOLayoutDocument(url: url).document()
    }

    func document() -> BrowserDocument? {
        let name = url.lastPathComponent
        if isArchive(at: 0) {
            let node = archiveNode(start: 0, end: reader.size, idPrefix: "archive/0")
            let root = factory.node(
                id: "archive-root",
                title: "Static Library",
                subtitle: name,
                summaryStyle: .group,
                range: nil,
                rows: { [url] in
                    [
                        BrowserDetailRow(key: "Source File", value: url.path),
                        BrowserDetailRow(key: "Container", value: "Static Library"),
                        BrowserDetailRow(key: "Targets", value: "1"),
                    ]
                },
                children: [{ node }]
            )
            return BrowserDocument(sourceName: name, kind: .archive, rootNodes: [root], hexSource: hexSource)
        }
        if let arches = fatArches() {
            return fatDocument(arches)
        }
        if let slice = RawMachOImage(reader: reader, base: 0) {
            let builder = MachOLayoutBuilder(slice: slice, idPrefix: "image", hexSource: hexSource)
            if slice.filetype == 0x6 {
                let title = "Dynamic Link Library (\(slice.platformArchitectureLabel))"
                let target = builder.imageNode(title: title)
                let root = factory.node(
                    id: "dynamic-library-root",
                    title: "Dynamic Link Library",
                    subtitle: name,
                    summaryStyle: .group,
                    range: nil,
                    rows: { [url] in
                        [
                            BrowserDetailRow(key: "Source File", value: url.path),
                            BrowserDetailRow(key: "Target", value: title),
                        ]
                    },
                    children: [{ target }]
                )
                return BrowserDocument(sourceName: name, kind: .machOFile, rootNodes: [root], hexSource: hexSource)
            }
            return BrowserDocument(sourceName: name, kind: .machOFile, rootNodes: [builder.imageNode(title: name)], hexSource: hexSource)
        }
        return nil
    }

    // MARK: Universal binaries

    struct FatArch {
        let index: Int
        let entryOffset: Int
        let cputype: Int32
        let cpusubtype: Int32
        let offset: Int
        let size: Int
        let align: UInt32
    }

    var isFat64: Bool { reader.u32BigEndian(at: 0) == MachOConstants.FAT_MAGIC_64 }

    func fatArches() -> [FatArch]? {
        guard let magic = reader.u32BigEndian(at: 0),
              magic == MachOConstants.FAT_MAGIC || magic == MachOConstants.FAT_MAGIC_64,
              let count = reader.u32BigEndian(at: 4),
              count > 0, count < 64 else { return nil }
        let is64 = magic == MachOConstants.FAT_MAGIC_64
        let entrySize = is64 ? 32 : 20
        var arches: [FatArch] = []
        for index in 0..<Int(count) {
            let entry = 8 + index * entrySize
            guard reader.contains(entry, count: entrySize) else { return nil }
            let offset = is64 ? Int(reader.u64BigEndian(at: entry + 8) ?? 0) : Int(reader.u32BigEndian(at: entry + 8) ?? 0)
            let size = is64 ? Int(reader.u64BigEndian(at: entry + 16) ?? 0) : Int(reader.u32BigEndian(at: entry + 12) ?? 0)
            let align = reader.u32BigEndian(at: entry + (is64 ? 24 : 16)) ?? 0
            // Java class files share 0xCAFEBABE; require every slice to fit inside the file.
            guard offset >= entry + entrySize, size > 0, offset + size <= reader.size else { return nil }
            arches.append(FatArch(
                index: index,
                entryOffset: entry,
                cputype: Int32(bitPattern: reader.u32BigEndian(at: entry) ?? 0),
                cpusubtype: Int32(bitPattern: reader.u32BigEndian(at: entry + 4) ?? 0),
                offset: offset,
                size: size,
                align: align
            ))
        }
        return arches
    }

    func fatHeaderRows(_ arches: [FatArch]) -> [BrowserDetailRow] {
        var rows = RowSink(reader: reader, swapped: true)
        rows.u32(0, "Magic Number", format: { $0 == MachOConstants.FAT_MAGIC_64 ? "FAT_MAGIC_64" : "FAT_MAGIC" })
        rows.u32(4, "Number of Architecture")
        for arch in arches {
            rows.nextGroup()
            let entry = arch.entryOffset
            rows.u32(entry, "CPU Type", format: { MachOConstants.cpuTypeName(Int32(bitPattern: $0)) })
            rows.u32(entry + 4, "CPU SubType", format: {
                MachOConstants.cpuSubtypeName(cpuType: arch.cputype, subtype: Int32(bitPattern: $0))
            })
            if isFat64 {
                rows.u64(entry + 8, "Offset", format: { hex($0) })
                rows.u64(entry + 16, "Size", format: { byteCount($0) })
                rows.u32(entry + 24, "Align", format: { "2^\($0) (\(UInt64(1) << UInt64(min($0, 63))))" })
                rows.u32(entry + 28, "Reserved")
            } else {
                rows.u32(entry + 8, "Offset", format: { hex($0) })
                rows.u32(entry + 12, "Size", format: { byteCount(UInt64($0)) })
                rows.u32(entry + 16, "Align", format: { "2^\($0) (\(UInt64(1) << UInt64(min($0, 63))))" })
            }
        }
        return rows.rows
    }

    func fatDocument(_ arches: [FatArch]) -> BrowserDocument {
        let name = url.lastPathComponent
        let allArchives = arches.allSatisfy { isArchive(at: $0.offset) }
        var children: [() -> BrowserNode] = []
        for arch in arches {
            let idPrefix = "fat/\(arch.index)"
            if isArchive(at: arch.offset) {
                children.append { archiveNode(start: arch.offset, end: arch.offset + arch.size, idPrefix: idPrefix) }
            } else if let slice = RawMachOImage(reader: reader, base: arch.offset, limit: arch.offset + arch.size) {
                children.append {
                    MachOLayoutBuilder(slice: slice, idPrefix: idPrefix, hexSource: hexSource)
                        .imageNode(title: "\(MachOConstants.fileTypeTitle(slice.filetype)) (\(slice.platformArchitectureLabel))")
                }
            } else {
                children.append {
                    let architecture = MachOConstants.displayArchitecture(cpuType: arch.cputype, subtype: arch.cpusubtype)
                    return hexDumpNode(id: idPrefix, title: "Unknown Slice (\(architecture))", start: arch.offset, length: arch.size)
                }
            }
        }
        let headerRows = fatHeaderRows(arches)
        let headerSize = 8 + arches.count * (isFat64 ? 32 : 20)
        let root = factory.node(
            id: allArchives ? "archive-root" : "fat-root",
            title: allArchives ? "Fat Archive" : name,
            subtitle: allArchives ? name : "Universal Binary",
            summaryStyle: .automatic,
            range: BrowserDataRange(start: 0, length: headerSize, within: reader.size),
            rows: { headerRows },
            children: children
        )
        return BrowserDocument(sourceName: name, kind: allArchives ? .archive : .fatFile, rootNodes: [root], hexSource: hexSource)
    }

    // MARK: Static archives

    struct ArchiveMember {
        let headerOffset: Int
        let name: String
        /// Bytes of the BSD `#1/N` long name stored in front of the member data.
        let longNameLength: Int
        let dataOffset: Int
        let dataSize: Int
        let declaredSize: Int

        var isSymbolTable: Bool {
            name.hasPrefix("__.SYMDEF") || name == "/" || name == "/SYM64/"
        }
    }

    func isArchive(at offset: Int) -> Bool {
        reader.bytes(at: offset, count: 8) == Data("!<arch>\n".utf8)
    }

    func archiveMembers(start: Int, end: Int) -> [ArchiveMember] {
        var members: [ArchiveMember] = []
        var cursor = start + 8
        var gnuNames: (offset: Int, size: Int)?
        while cursor + 60 <= end {
            let rawName = reader.fixedString(at: cursor, count: 16) ?? ""
            let sizeText = (reader.fixedString(at: cursor + 48, count: 10) ?? "").trimmingCharacters(in: .whitespaces)
            guard let declaredSize = Int(sizeText), declaredSize >= 0 else { break }
            var name = rawName.trimmingCharacters(in: .whitespaces)
            var longNameLength = 0
            if name.hasPrefix("#1/"), let length = Int(name.dropFirst(3)) {
                longNameLength = min(length, declaredSize)
                name = reader.fixedString(at: cursor + 60, count: longNameLength) ?? name
            } else if name == "//" {
                gnuNames = (cursor + 60, declaredSize)
            } else if name.hasPrefix("/"), name.count > 1, let index = Int(name.dropFirst()), let table = gnuNames, index < table.size {
                let resolved = reader.cString(at: table.offset + index, limit: table.offset + table.size)?.string ?? name
                name = resolved.split(separator: "\n").first.map(String.init) ?? resolved
                if name.hasSuffix("/") { name.removeLast() }
            } else if name.hasSuffix("/"), name != "/", name != "//", name != "/SYM64/" {
                name.removeLast()
            }
            let dataOffset = cursor + 60 + longNameLength
            let dataSize = max(0, min(declaredSize - longNameLength, end - dataOffset))
            members.append(ArchiveMember(
                headerOffset: cursor,
                name: name,
                longNameLength: longNameLength,
                dataOffset: dataOffset,
                dataSize: dataSize,
                declaredSize: declaredSize
            ))
            cursor += 60 + declaredSize
            if cursor % 2 == 1 { cursor += 1 }
        }
        return members
    }

    func archiveNode(start: Int, end: Int, idPrefix: String) -> BrowserNode {
        let members = archiveMembers(start: start, end: end)
        let firstImage = members.lazy.compactMap { member -> RawMachOImage? in
            guard member.isSymbolTable == false else { return nil }
            return RawMachOImage(reader: reader, base: member.dataOffset, limit: member.dataOffset + member.dataSize)
        }.first
        let label = firstImage?.platformArchitectureLabel ?? "unknown"
        let swapped = firstImage?.swapped ?? false

        var children: [() -> BrowserNode] = [{
            factory.node(
                id: idPrefix + "/start",
                title: "Start",
                range: BrowserDataRange(start: start, length: 8, within: reader.size),
                rows: { [reader] in
                    var rows = RowSink(reader: reader)
                    rows.bytes(start, 8, "Archive Signature", "!<arch>\\n")
                    return rows.rows
                }
            )
        }]
        var objectCount = 0
        var symbolCount = 0
        for (index, member) in members.enumerated() {
            let memberID = idPrefix + "/member/\(index)"
            if member.isSymbolTable {
                children.append { memberHeaderNode(member, id: memberID + "/header", title: "Symtab Header") }
                let table = symbolTable(member, archiveStart: start, members: members, swapped: swapped)
                symbolCount += table.entries.count
                children.append { symbolTableNode(table, id: memberID + "/symbols") }
                children.append { archiveStringTableNode(table, id: memberID + "/strings") }
            } else if member.name == "//" {
                children.append {
                    let lines = reader.bytes(at: member.dataOffset, count: member.dataSize).map { String(decoding: $0, as: UTF8.self) } ?? ""
                    let names = lines.split(separator: "\n").map(String.init)
                    return factory.node(
                        id: memberID,
                        title: "Long Names",
                        range: BrowserDataRange(start: member.headerOffset, length: 60 + member.declaredSize, within: reader.size),
                        rows: { memberHeaderRows(member) + names.map { BrowserDetailRow(key: "Name", value: $0, groupIdentifier: 1) } }
                    )
                }
            } else {
                objectCount += 1
                children.append { memberNode(member, id: memberID) }
            }
        }

        let architecture = firstImage?.architecture ?? "unknown"
        let rows = [
            BrowserDetailRow(key: "Architecture", value: architecture),
            BrowserDetailRow(key: "Platform", value: firstImage?.platformName ?? "unknown"),
            BrowserDetailRow(key: "Members", value: "\(objectCount)"),
            BrowserDetailRow(key: "Symbols", value: "\(symbolCount)"),
            BrowserDetailRow(key: "Offset", value: hex(UInt64(start)), groupIdentifier: 1),
            BrowserDetailRow(key: "Size", value: byteCount(UInt64(end - start)), groupIdentifier: 1),
        ]
        return factory.node(
            id: idPrefix,
            title: "Static Library (\(label))",
            subtitle: "\(objectCount) members",
            range: BrowserDataRange(start: start, length: end - start, within: reader.size),
            rows: { rows },
            children: children
        )
    }

    func memberHeaderRows(_ member: ArchiveMember) -> [BrowserDetailRow] {
        var rows = RowSink(reader: reader)
        let offset = member.headerOffset
        func text(_ start: Int, _ count: Int) -> String {
            (reader.fixedString(at: start, count: count) ?? "").trimmingCharacters(in: .whitespaces)
        }
        rows.bytes(offset, 16, "Name", text(offset, 16))
        let dateText = text(offset + 16, 12)
        let date = TimeInterval(dateText).map { Date(timeIntervalSince1970: $0) }
        rows.bytes(offset + 16, 12, "Time Stamp", date.map { "\(dateText) (\(Self.dateFormatter.string(from: $0)))" } ?? dateText)
        rows.bytes(offset + 28, 6, "UserID", text(offset + 28, 6))
        rows.bytes(offset + 34, 6, "GroupID", text(offset + 34, 6))
        rows.bytes(offset + 40, 8, "Mode", text(offset + 40, 8))
        rows.bytes(offset + 48, 10, "Size", text(offset + 48, 10))
        rows.bytes(offset + 58, 2, "End Header", "`\\n")
        if member.longNameLength > 0 {
            rows.bytes(offset + 60, member.longNameLength, "Long Name", member.name)
        }
        return rows.rows
    }

    nonisolated(unsafe) static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter
    }()

    func memberHeaderNode(_ member: ArchiveMember, id: String, title: String) -> BrowserNode {
        factory.node(
            id: id,
            title: title,
            range: BrowserDataRange(start: member.headerOffset, length: 60 + member.longNameLength, within: reader.size),
            rows: { memberHeaderRows(member) }
        )
    }

    func memberNode(_ member: ArchiveMember, id: String) -> BrowserNode {
        let header: () -> BrowserNode = { memberHeaderNode(member, id: id + "/header", title: "Object Header") }
        guard let slice = RawMachOImage(reader: reader, base: member.dataOffset, limit: member.dataOffset + member.dataSize) else {
            let dump = hexDumpNode(id: id + "/data", title: "Data", start: member.dataOffset, length: member.dataSize)
            return factory.node(
                id: id,
                title: member.name,
                range: BrowserDataRange(start: member.headerOffset, length: 60 + member.declaredSize, within: reader.size),
                rows: { memberHeaderRows(member) },
                children: [header, { dump }]
            )
        }
        let builder = MachOLayoutBuilder(slice: slice, idPrefix: id, hexSource: hexSource)
        let rows = builder.summaryRows()
        return factory.node(
            id: id,
            title: member.name,
            subtitle: builder.summary,
            range: BrowserDataRange(start: member.headerOffset, length: 60 + member.declaredSize, within: reader.size),
            rows: { rows },
            children: [header] + builder.imageChildren()
        )
    }

    // MARK: Archive symbol table

    struct ArchiveSymbolTable {
        struct Entry {
            let offset: Int
            let stringIndex: UInt64
            let memberOffset: UInt64
            let name: String
            let memberName: String
        }

        let member: ArchiveMember
        let is64: Bool
        let isGNU: Bool
        let swapped: Bool
        let entrySize: Int
        let entries: [Entry]
        let tableStart: Int
        let tableSize: Int
        let stringsSizeOffset: Int?
        let stringsStart: Int
        let stringsSize: Int
    }

    func symbolTable(_ member: ArchiveMember, archiveStart: Int, members: [ArchiveMember], swapped: Bool) -> ArchiveSymbolTable {
        let memberNames = Dictionary(members.map { (UInt64($0.headerOffset - archiveStart), $0.name) }, uniquingKeysWith: { first, _ in first })
        let start = member.dataOffset
        let end = start + member.dataSize
        var entries: [ArchiveSymbolTable.Entry] = []

        if member.name == "/" || member.name == "/SYM64/" {
            // GNU: big-endian count, member offsets, then NUL-separated names.
            let is64 = member.name == "/SYM64/"
            let width = is64 ? 8 : 4
            let count = Int(min(UInt64(is64 ? reader.u64BigEndian(at: start) ?? 0 : UInt64(reader.u32BigEndian(at: start) ?? 0)), UInt64(member.dataSize / width)))
            let stringsStart = start + width + count * width
            var nameCursor = stringsStart
            for index in 0..<count {
                let offset = start + width + index * width
                let memberOffset = is64 ? reader.u64BigEndian(at: offset) ?? 0 : UInt64(reader.u32BigEndian(at: offset) ?? 0)
                let name = reader.cString(at: nameCursor, limit: end)
                entries.append(.init(
                    offset: offset,
                    stringIndex: UInt64(nameCursor - stringsStart),
                    memberOffset: memberOffset,
                    name: name?.string ?? "",
                    memberName: memberNames[memberOffset] ?? hex(memberOffset)
                ))
                nameCursor += (name?.length ?? 0) + 1
            }
            return ArchiveSymbolTable(
                member: member, is64: is64, isGNU: true, swapped: false, entrySize: width, entries: entries,
                tableStart: start, tableSize: width + count * width,
                stringsSizeOffset: nil, stringsStart: stringsStart, stringsSize: max(0, end - stringsStart)
            )
        }

        // BSD: ranlib array size, ranlib entries, string table size, strings.
        let is64 = member.name.hasPrefix("__.SYMDEF_64")
        let width = is64 ? 8 : 4
        let entrySize = width * 2
        func read(_ offset: Int) -> UInt64 {
            is64 ? reader.u64(at: offset, swapped: swapped) ?? 0 : UInt64(reader.u32(at: offset, swapped: swapped) ?? 0)
        }
        let arraySize = Int(min(read(start), UInt64(member.dataSize)))
        let count = arraySize / entrySize
        let stringsSizeOffset = start + width + arraySize
        let stringsSize = Int(min(read(stringsSizeOffset), UInt64(max(0, end - stringsSizeOffset - width))))
        let stringsStart = stringsSizeOffset + width
        for index in 0..<count {
            let offset = start + width + index * entrySize
            let strx = read(offset)
            let memberOffset = read(offset + width)
            let name = strx < UInt64(stringsSize) ? reader.cString(at: stringsStart + Int(strx), limit: stringsStart + stringsSize)?.string : nil
            entries.append(.init(
                offset: offset,
                stringIndex: strx,
                memberOffset: memberOffset,
                name: name ?? "",
                memberName: memberNames[memberOffset] ?? hex(memberOffset)
            ))
        }
        return ArchiveSymbolTable(
            member: member, is64: is64, isGNU: false, swapped: swapped, entrySize: entrySize, entries: entries,
            tableStart: start, tableSize: width + arraySize,
            stringsSizeOffset: stringsSizeOffset, stringsStart: stringsStart, stringsSize: stringsSize
        )
    }

    func symbolTableNode(_ table: ArchiveSymbolTable, id: String) -> BrowserNode {
        let entries = table.entries
        let width = table.is64 ? 8 : 4
        let rowsPerEntry = table.isGNU ? 1 : 2
        let reader = reader
        func data(_ offset: Int) -> String? {
            let value: UInt64?
            if table.isGNU {
                value = width == 8 ? reader.u64BigEndian(at: offset) : reader.u32BigEndian(at: offset).map(UInt64.init)
            } else {
                value = reader.unsigned(at: offset, size: width, swapped: table.swapped)
            }
            return value.map { padded($0, width: width) }
        }
        return factory.indexedNode(
            id: id,
            title: "Symbol Table",
            range: BrowserDataRange(start: table.tableStart, length: table.tableSize, within: reader.size),
            rowCount: 1 + entries.count * rowsPerEntry,
            row: { index in
                if index == 0 {
                    return BrowserDetailRow(
                        key: table.isGNU ? "Number of Symbols" : "Size",
                        value: table.isGNU ? "\(entries.count)" : byteCount(UInt64(entries.count * table.entrySize)),
                        dataPreview: data(table.tableStart),
                        rawAddress: UInt64(table.tableStart)
                    )
                }
                let entryIndex = (index - 1) / rowsPerEntry
                let entry = entries[entryIndex]
                let group = UInt(entryIndex + 1)
                if table.isGNU {
                    return BrowserDetailRow(
                        key: entry.name,
                        value: entry.memberName,
                        dataPreview: data(entry.offset),
                        rawAddress: UInt64(entry.offset),
                        groupIdentifier: group
                    )
                }
                if (index - 1) % 2 == 0 {
                    return BrowserDetailRow(
                        key: "String Offset",
                        value: entry.name,
                        dataPreview: data(entry.offset),
                        rawAddress: UInt64(entry.offset),
                        groupIdentifier: group
                    )
                }
                return BrowserDetailRow(
                    key: "Object Offset",
                    value: entry.memberName,
                    dataPreview: data(entry.offset + width),
                    rawAddress: UInt64(entry.offset + width),
                    groupIdentifier: group
                )
            }
        )
    }

    func archiveStringTableNode(_ table: ArchiveSymbolTable, id: String) -> BrowserNode {
        let reader = reader
        let start = table.stringsStart
        let offsets = table.stringsSize > 0 ? reader.stringOffsets(from: start, to: start + table.stringsSize) : []
        let prefixRows = table.stringsSizeOffset.map { sizeOffset -> [BrowserDetailRow] in
            var rows = RowSink(reader: reader, swapped: table.swapped)
            rows.field(sizeOffset, table.is64 ? 8 : 4, "String Table Size", byteCount(UInt64(table.stringsSize)))
            return rows.rows
        } ?? []
        let rangeStart = table.stringsSizeOffset ?? start
        return factory.indexedNode(
            id: id,
            title: "String Table",
            range: BrowserDataRange(start: rangeStart, length: start + table.stringsSize - rangeStart, within: reader.size),
            rowCount: prefixRows.count + offsets.count,
            row: { index in
                if index < prefixRows.count { return prefixRows[index] }
                let relative = Int(offsets[index - prefixRows.count])
                let offset = start + relative
                let value = reader.cString(at: offset, limit: start + table.stringsSize)
                return BrowserDetailRow(
                    key: "[\(relative)]",
                    value: escapedDisplayString(value?.string ?? ""),
                    dataPreview: reader.hexString(at: offset, count: (value?.length ?? 0) + 1),
                    rawAddress: UInt64(offset),
                    groupIdentifier: 1
                )
            }
        )
    }

    // MARK: Helpers

    func hexDumpNode(id: String, title: String, start: Int, length: Int) -> BrowserNode {
        let reader = reader
        let length = max(0, min(length, reader.size - start))
        let count = (length + 15) / 16
        return factory.indexedNode(
            id: id,
            title: title,
            range: BrowserDataRange(start: start, length: length, within: reader.size),
            rowCount: count,
            row: { index in
                let offset = start + index * 16
                let size = min(16, start + length - offset)
                let bytes = reader.bytes(at: offset, count: size) ?? Data()
                return BrowserDetailRow(
                    key: asciiPreview(bytes),
                    value: "",
                    dataPreview: bytes.map { String(format: "%02X", $0) }.joined(),
                    rawAddress: UInt64(offset)
                )
            }
        )
    }
}

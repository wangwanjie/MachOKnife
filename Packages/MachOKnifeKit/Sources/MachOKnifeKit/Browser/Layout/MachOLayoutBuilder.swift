import Foundation

/// Builds a MachOView-style, lazily materialized node tree for one Mach-O image.
struct MachOLayoutBuilder {
    let slice: RawMachOImage
    let idPrefix: String
    let factory: LayoutNodeFactory

    init(slice: RawMachOImage, idPrefix: String, hexSource: BrowserHexSource) {
        self.slice = slice
        self.idPrefix = idPrefix
        self.factory = LayoutNodeFactory(hexSource: hexSource, rva: { [slice] in slice.rva(forFileOffset: $0) })
    }

    func id(_ components: String...) -> String {
        ([idPrefix] + components).joined(separator: "/")
    }

    func sink() -> RowSink {
        RowSink(slice: slice)
    }

    func range(_ start: Int, _ length: Int) -> BrowserDataRange? {
        BrowserDataRange(start: start, length: length, within: slice.limit)
    }

    /// Range for a (slice-relative offset, size) pair from a load command.
    func linkEditRange(_ offset: UInt32, _ size: UInt32) -> BrowserDataRange? {
        guard size > 0, let start = slice.absolute(UInt64(offset)) else { return nil }
        return range(start, Int(size))
    }

    // MARK: Image

    var summary: String {
        [
            MachOConstants.magicName(slice.magic),
            MachOConstants.cpuTypeName(slice.cputype),
            MachOConstants.fileTypeName(slice.filetype),
        ].joined(separator: "  •  ")
    }

    func summaryRows(prefix: [BrowserDetailRow] = []) -> [BrowserDetailRow] {
        var rows = prefix
        let group: UInt = prefix.last.map { $0.groupIdentifier + 1 } ?? 0
        func add(_ key: String, _ value: String) {
            rows.append(BrowserDetailRow(key: key, value: value, groupIdentifier: group))
        }
        add("Magic", MachOConstants.magicName(slice.magic))
        add("CPU Type", MachOConstants.cpuTypeName(slice.cputype))
        add("CPU SubType", MachOConstants.cpuSubtypeName(cpuType: slice.cputype, subtype: slice.cpusubtype))
        add("Architecture", slice.architecture)
        add("File Type", MachOConstants.fileTypeName(slice.filetype))
        add("Load Commands", "\(slice.commands.count)")
        add("Segments", "\(slice.segments.count)")
        add("Sections", "\(slice.sections.count)")
        if let symtab = slice.symtab {
            add("Symbols", "\(symtab.nsyms)")
        }
        add("Dylibs", "\(slice.dylibs.count)")
        if let platform = slice.platform {
            add("Platform", MachOConstants.platformName(platform))
        }
        if let uuid = slice.uuid {
            add("UUID", uuid)
        }
        if let installName = slice.installName {
            add("Install Name", installName)
        }
        add("Offset", hex(UInt64(slice.base)))
        add("Size", byteCount(UInt64(slice.size)))
        return rows
    }

    /// Node for the whole image: header, load commands, segments, sections and link-edit data.
    func imageNode(title: String, subtitle: String? = nil, extraRows: [BrowserDetailRow] = []) -> BrowserNode {
        let rows = summaryRows(prefix: extraRows)
        return factory.node(
            id: idPrefix,
            title: title,
            subtitle: subtitle ?? summary,
            range: range(slice.base, slice.size),
            rows: { rows },
            children: imageChildren()
        )
    }

    func imageChildren() -> [() -> BrowserNode] {
        var children: [() -> BrowserNode] = [
            { headerNode() },
            { loadCommandsNode() },
        ]
        if slice.segments.isEmpty == false {
            children.append { segmentsNode() }
        }
        for section in slice.sections {
            children.append { sectionNode(section) }
        }
        children.append(contentsOf: linkEditChildren())
        return children
    }

    // MARK: Header

    func headerNode() -> BrowserNode {
        let slice = slice
        return factory.node(
            id: id("header"),
            title: slice.is64 ? "Mach64 Header" : "Mach Header",
            range: range(slice.base, slice.headerSize),
            rows: {
                var rows = RowSink(slice: slice)
                let base = slice.base
                rows.field(base, 4, "Magic Number", MachOConstants.magicName(slice.magic))
                rows.field(base + 4, 4, "CPU Type", MachOConstants.cpuTypeName(slice.cputype))
                rows.field(base + 8, 4, "CPU SubType", MachOConstants.cpuSubtypeName(cpuType: slice.cputype, subtype: slice.cpusubtype))
                for (bit, name) in MachOConstants.cpuSubtypeCapabilityNames(cpuType: slice.cputype, subtype: slice.cpusubtype) {
                    rows.note(padded(UInt64(bit), width: 4), name)
                }
                rows.field(base + 12, 4, "File Type", MachOConstants.fileTypeName(slice.filetype))
                rows.field(base + 16, 4, "Number of Load Commands", "\(slice.ncmds)")
                rows.field(base + 20, 4, "Size of Load Commands", "\(slice.sizeofcmds)")
                rows.field(base + 24, 4, "Flags", hex(slice.flags))
                rows.flags(slice.flags, MachOConstants.headerFlags)
                if slice.is64 {
                    rows.field(base + 28, 4, "Reserved", hex(slice.reserved ?? 0))
                }
                return rows.rows
            }
        )
    }

    // MARK: Segments

    func segmentsNode() -> BrowserNode {
        let segments = slice.segments
        let slice = slice
        return factory.node(
            id: id("segments"),
            title: "Segments (\(segments.count))",
            summaryStyle: .group,
            range: nil,
            rows: {
                segments.enumerated().map { index, segment in
                    BrowserDetailRow(
                        key: segment.name.isEmpty ? "(unnamed)" : segment.name,
                        value: "\(hex(segment.vmaddr))-\(hex(segment.vmaddr + segment.vmsize))  \(MachOConstants.vmProtectionShort(segment.initprot))/\(MachOConstants.vmProtectionShort(segment.maxprot))  file \(hex(segment.fileoff))+\(hex(segment.filesize))",
                        rawAddress: slice.absolute(segment.fileoff).map { UInt64($0) },
                        rvaAddress: segment.vmaddr,
                        groupIdentifier: UInt(index)
                    )
                }
            },
            children: segments.indices.map { index in { segmentNode(index) } }
        )
    }

    func segmentNode(_ index: Int) -> BrowserNode {
        let segment = slice.segments[index]
        let slice = slice
        let start = slice.absolute(segment.fileoff)
        let dataRange = start.flatMap { range($0, Int(clamping: segment.filesize)) }
        let sections = Array(slice.sections[segment.sectionRange])
        return factory.node(
            id: id("segments", "\(index)"),
            title: segment.name.isEmpty ? "(unnamed segment)" : segment.name,
            subtitle: "\(hex(segment.vmaddr)) • \(MachOConstants.vmProtectionShort(segment.initprot))",
            range: dataRange,
            rvaAddress: segment.vmaddr,
            rows: {
                var rows = RowSink(slice: slice)
                rows.note("Segment Name", segment.name)
                rows.note("VM Address", hex(segment.vmaddr))
                rows.note("VM Size", byteCount(segment.vmsize))
                rows.note("File Offset", hex(segment.fileoff))
                rows.note("File Size", byteCount(segment.filesize))
                rows.note("Maximum VM Protection", MachOConstants.vmProtection(segment.maxprot))
                rows.note("Initial VM Protection", MachOConstants.vmProtection(segment.initprot))
                rows.note("Number of Sections", "\(segment.nsects)")
                rows.note("Flags", hex(segment.flags))
                rows.flags(segment.flags, MachOConstants.segmentFlags)
                for section in sections {
                    rows.nextGroup()
                    let offset = section.isZerofill ? nil : slice.absolute(UInt64(section.offset))
                    rows.append(BrowserDetailRow(
                        key: section.name,
                        value: "\(hex(section.addr)) size \(byteCount(section.size)) \(MachOConstants.sectionTypeName(section.type))",
                        rawAddress: offset.map { UInt64($0) },
                        rvaAddress: section.addr,
                        groupIdentifier: rows.group
                    ))
                }
                return rows.rows
            }
        )
    }
}

import Foundation

extension MachOLayoutBuilder {
    /// Code signature blobs are big-endian regardless of the image byte order.
    func bigEndianSink() -> RowSink {
        RowSink(reader: slice.reader, swapped: true, rva: { _ in nil })
    }

    func be32(_ offset: Int) -> UInt32 { slice.reader.u32BigEndian(at: offset) ?? 0 }

    func codeSignatureNode(_ data: RawMachOImage.LinkEditData) -> BrowserNode {
        guard let dataRange = linkEditRange(data.dataoff, data.datasize) else {
            return rawLinkEditNode(data)
        }
        let start = dataRange.offset
        let end = start + dataRange.length
        let magic = be32(start)
        guard magic == 0xFADE_0CC0 || magic == 0xFADE_0B02 else {
            return blobNode(start: start, end: end, nodeID: id("codesign"), title: "Code Signature")
        }
        let count = Int(min(be32(start + 8), 64))
        var children: [() -> BrowserNode] = []
        for index in 0..<count {
            let entry = start + 12 + index * 8
            guard entry + 8 <= end else { break }
            let type = be32(entry)
            let offset = Int(be32(entry + 4))
            let blobStart = start + offset
            guard blobStart + 8 <= end else { continue }
            let blobEnd = min(end, blobStart + Int(be32(blobStart + 4)))
            children.append {
                blobNode(
                    start: blobStart,
                    end: blobEnd,
                    nodeID: id("codesign", "\(index)"),
                    title: Self.codeSignatureBlobTitle(slot: type, magic: be32(blobStart))
                )
            }
        }
        return factory.node(
            id: id("codesign"),
            title: "Code Signature",
            range: dataRange,
            rows: {
                var rows = bigEndianSink()
                rows.u32(start, "Magic", format: { MachOConstants.codeSignatureMagicName($0) })
                rows.u32(start + 4, "Length", format: { byteCount(UInt64($0)) })
                rows.u32(start + 8, "Count")
                for index in 0..<count {
                    let entry = start + 12 + index * 8
                    guard entry + 8 <= end else { break }
                    rows.nextGroup()
                    rows.u32(entry, "Type", format: { MachOConstants.codeSignatureSlotName($0) })
                    rows.u32(entry + 4, "Offset", format: { hex($0) })
                }
                return rows.rows
            },
            children: children
        )
    }

    static func codeSignatureBlobTitle(slot: UInt32, magic: UInt32) -> String {
        switch magic {
        case 0xFADE_0C02:
            return slot == 0 ? "Code Directory" : "Alternate Code Directory"
        case 0xFADE_0C01: return "Requirements"
        case 0xFADE_7171: return "Entitlements"
        case 0xFADE_7172: return "DER Entitlements"
        case 0xFADE_7173: return "Launch Constraint"
        case 0xFADE_0B01: return "Signature (CMS)"
        default: return MachOConstants.codeSignatureSlotName(slot)
        }
    }

    func blobNode(start: Int, end: Int, nodeID: String, title: String) -> BrowserNode {
        let magic = be32(start)
        let dataRange = range(start, end - start)
        switch magic {
        case 0xFADE_0C02:
            return codeDirectoryNode(start: start, end: end, nodeID: nodeID, title: title)
        case 0xFADE_0C01:
            return requirementsNode(start: start, end: end, nodeID: nodeID, title: title)
        case 0xFADE_7171:
            let text = slice.reader.bytes(at: start + 8, count: max(0, end - start - 8)).map { String(decoding: $0, as: UTF8.self) } ?? ""
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            return factory.node(
                id: nodeID,
                title: title,
                range: dataRange,
                rows: {
                    var rows = bigEndianSink()
                    rows.u32(start, "Magic", format: { MachOConstants.codeSignatureMagicName($0) })
                    rows.u32(start + 4, "Length", format: { byteCount(UInt64($0)) })
                    rows.nextGroup()
                    var cursor = start + 8
                    for line in lines {
                        let length = line.utf8.count
                        if length > 0 {
                            rows.bytes(cursor, length, "", line)
                        }
                        cursor += length + 1
                    }
                    return rows.rows
                }
            )
        default:
            let content = hexDumpContent(start: start + 8, length: max(0, end - start - 8))
            return factory.node(
                id: nodeID,
                title: title,
                range: dataRange,
                rows: {
                    var rows = bigEndianSink()
                    rows.u32(start, "Magic", format: { MachOConstants.codeSignatureMagicName($0) })
                    rows.u32(start + 4, "Length", format: { byteCount(UInt64($0)) })
                    rows.nextGroup()
                    for index in 0..<min(content.count, 100_000) {
                        rows.append(content.row(index))
                    }
                    return rows.rows
                }
            )
        }
    }

    func codeDirectoryNode(start: Int, end: Int, nodeID: String, title: String) -> BrowserNode {
        let reader = slice.reader
        let version = be32(start + 8)
        let hashOffset = Int(be32(start + 16))
        let specialSlots = Int(be32(start + 24))
        let codeSlots = Int(be32(start + 28))
        let hashSize = Int(reader.u8(at: start + 36) ?? 0)
        let hashType = reader.u8(at: start + 37) ?? 0
        let pageShift = reader.u8(at: start + 39) ?? 0

        var children: [() -> BrowserNode] = []
        if specialSlots > 0, hashSize > 0 {
            children.append {
                factory.indexedNode(
                    id: nodeID + "/special",
                    title: "Special Slots (\(specialSlots))",
                    range: range(start + hashOffset - specialSlots * hashSize, specialSlots * hashSize),
                    rowCount: specialSlots,
                    row: { index in
                        let slot = specialSlots - index
                        let offset = start + hashOffset - slot * hashSize
                        let digest = reader.hexString(at: offset, count: hashSize, maximumBytes: 64)
                        let empty = digest.allSatisfy { $0 == "0" }
                        return BrowserDetailRow(
                            key: "-\(slot) \(MachOConstants.specialSlotName(slot))",
                            value: empty ? "Not Bound" : digest,
                            dataPreview: reader.hexString(at: offset, count: hashSize, maximumBytes: 32),
                            rawAddress: UInt64(offset)
                        )
                    }
                )
            }
        }
        if codeSlots > 0, hashSize > 0 {
            let pageSize = pageShift == 0 ? 0 : UInt64(1) << UInt64(pageShift)
            children.append {
                factory.indexedNode(
                    id: nodeID + "/code",
                    title: "Code Slots (\(codeSlots))",
                    range: range(start + hashOffset, codeSlots * hashSize),
                    rowCount: codeSlots,
                    row: { index in
                        let offset = start + hashOffset + index * hashSize
                        return BrowserDetailRow(
                            key: pageSize > 0 ? "Page \(index) (\(hex(UInt64(index) * pageSize)))" : "Slot \(index)",
                            value: reader.hexString(at: offset, count: hashSize, maximumBytes: 64),
                            dataPreview: reader.hexString(at: offset, count: hashSize, maximumBytes: 32),
                            rawAddress: UInt64(offset)
                        )
                    }
                )
            }
        }

        return factory.node(
            id: nodeID,
            title: title,
            range: range(start, end - start),
            rows: {
                var rows = bigEndianSink()
                func string(_ fieldOffset: Int, _ key: String, _ stringKey: String) {
                    let relative = Int(rows.u32(fieldOffset, key, format: { hex($0) }))
                    if relative > 0, let value = reader.cString(at: start + relative, limit: end) {
                        rows.bytes(start + relative, value.length + 1, stringKey, value.string)
                    }
                }
                rows.u32(start, "Magic", format: { MachOConstants.codeSignatureMagicName($0) })
                rows.u32(start + 4, "Length", format: { byteCount(UInt64($0)) })
                rows.u32(start + 8, "Version", format: { hex($0) })
                let flags = rows.u32(start + 12, "Flags", format: { hex($0) })
                rows.flags(flags, MachOConstants.codeDirectoryFlags)
                rows.u32(start + 16, "Hash Offset", format: { hex($0) })
                string(start + 20, "Identifier Offset", "Identifier")
                rows.u32(start + 24, "Special Slots")
                rows.u32(start + 28, "Code Slots")
                rows.u32(start + 32, "Code Limit", format: { byteCount(UInt64($0)) })
                rows.u8(start + 36, "Hash Size")
                rows.u8(start + 37, "Hash Type", format: { MachOConstants.hashTypeName($0) })
                rows.u8(start + 38, "Platform")
                rows.u8(start + 39, "Page Size", format: { $0 == 0 ? "0 (infinite)" : "2^\($0) (\(1 << Int($0)))" })
                rows.u32(start + 40, "Spare2")
                if version >= 0x20100 { rows.u32(start + 44, "Scatter Offset", format: { hex($0) }) }
                if version >= 0x20200 { string(start + 48, "Team ID Offset", "Team ID") }
                if version >= 0x20300 {
                    rows.u32(start + 52, "Spare3")
                    rows.u64(start + 56, "Code Limit 64", format: { byteCount($0) })
                }
                if version >= 0x20400 {
                    rows.u64(start + 64, "Exec Segment Base", format: { hex($0) })
                    rows.u64(start + 72, "Exec Segment Limit", format: { byteCount($0) })
                    let execFlags = rows.u64(start + 80, "Exec Segment Flags", format: { hex($0) })
                    rows.flags(execFlags, MachOConstants.execSegmentFlags)
                }
                if version >= 0x20500 {
                    rows.u32(start + 88, "Runtime", format: { value in
                        value == 0 ? "0" : "\(value >> 16).\((value >> 8) & 0xFF).\(value & 0xFF)"
                    })
                    rows.u32(start + 92, "Pre-Encrypt Offset", format: { hex($0) })
                }
                if version >= 0x20600 {
                    rows.u8(start + 96, "Linkage Hash Type", format: { MachOConstants.hashTypeName($0) })
                    rows.u8(start + 97, "Linkage Application Type")
                    rows.u16(start + 98, "Linkage Application SubType")
                    rows.u32(start + 100, "Linkage Offset", format: { hex($0) })
                    rows.u32(start + 104, "Linkage Size")
                }
                rows.nextGroup()
                rows.note("Hash Algorithm", MachOConstants.hashTypeName(hashType))
                return rows.rows
            },
            children: children
        )
    }

    func requirementsNode(start: Int, end: Int, nodeID: String, title: String) -> BrowserNode {
        let count = Int(min(be32(start + 8), 32))
        var children: [() -> BrowserNode] = []
        for index in 0..<count {
            let entry = start + 12 + index * 8
            guard entry + 8 <= end else { break }
            let type = be32(entry)
            let requirementStart = start + Int(be32(entry + 4))
            guard requirementStart + 12 <= end else { continue }
            let requirementEnd = min(end, requirementStart + Int(be32(requirementStart + 4)))
            children.append {
                let content = hexDumpContent(start: requirementStart + 12, length: max(0, requirementEnd - requirementStart - 12))
                return factory.node(
                    id: nodeID + "/\(index)",
                    title: Self.requirementTypeName(type),
                    range: range(requirementStart, requirementEnd - requirementStart),
                    rows: {
                        var rows = bigEndianSink()
                        rows.u32(requirementStart, "Magic", format: { MachOConstants.codeSignatureMagicName($0) })
                        rows.u32(requirementStart + 4, "Length", format: { byteCount(UInt64($0)) })
                        rows.u32(requirementStart + 8, "Kind", format: { $0 == 1 ? "kReqExpression" : "\($0)" })
                        rows.nextGroup()
                        for row in 0..<min(content.count, 10_000) {
                            rows.append(content.row(row))
                        }
                        return rows.rows
                    }
                )
            }
        }
        return factory.node(
            id: nodeID,
            title: title,
            range: range(start, end - start),
            rows: {
                var rows = bigEndianSink()
                rows.u32(start, "Magic", format: { MachOConstants.codeSignatureMagicName($0) })
                rows.u32(start + 4, "Length", format: { byteCount(UInt64($0)) })
                rows.u32(start + 8, "Count")
                for index in 0..<count {
                    let entry = start + 12 + index * 8
                    guard entry + 8 <= end else { break }
                    rows.nextGroup()
                    rows.u32(entry, "Type", format: { Self.requirementTypeName($0) })
                    rows.u32(entry + 4, "Offset", format: { hex($0) })
                }
                return rows.rows
            },
            children: children
        )
    }

    static func requirementTypeName(_ type: UInt32) -> String {
        switch type {
        case 1: return "Host Requirement"
        case 2: return "Guest Requirement"
        case 3: return "Designated Requirement"
        case 4: return "Library Requirement"
        case 5: return "Plugin Requirement"
        default: return "Requirement \(type)"
        }
    }
}

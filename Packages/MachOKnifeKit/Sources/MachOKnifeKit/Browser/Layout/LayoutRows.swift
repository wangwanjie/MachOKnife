import Foundation

/// Accumulates MachOView-style detail rows: absolute offset, data bytes, description, value.
struct RowSink {
    let reader: MachOByteReader
    let swapped: Bool
    let rva: (Int) -> UInt64?
    private(set) var rows: [BrowserDetailRow] = []
    var group: UInt = 0

    init(reader: MachOByteReader, swapped: Bool = false, rva: @escaping (Int) -> UInt64? = { _ in nil }) {
        self.reader = reader
        self.swapped = swapped
        self.rva = rva
    }

    init(slice: RawMachOImage) {
        self.init(reader: slice.reader, swapped: slice.swapped, rva: { [slice] in slice.rva(forFileOffset: $0) })
    }

    mutating func nextGroup() {
        group += 1
    }

    /// Integer field: the Data column shows the decoded value in hex, padded to the field width.
    mutating func field(_ offset: Int, _ size: Int, _ key: String, _ value: String) {
        append(offset, integerData(offset, size), key, value)
    }

    /// Byte field (names, UUIDs, hashes): the Data column shows the raw bytes.
    mutating func bytes(_ offset: Int, _ size: Int, _ key: String, _ value: String) {
        append(offset, reader.hexString(at: offset, count: size, maximumBytes: 32), key, value)
    }

    /// Row without its own bytes, used for flag breakdowns and derived values.
    mutating func note(_ key: String, _ value: String) {
        rows.append(BrowserDetailRow(key: key, value: value, groupIdentifier: group))
    }

    mutating func append(_ offset: Int?, _ data: String?, _ key: String, _ value: String) {
        rows.append(BrowserDetailRow(
            key: key,
            value: value,
            dataPreview: data,
            rawAddress: offset.map { UInt64($0) },
            rvaAddress: offset.flatMap(rva),
            groupIdentifier: group
        ))
    }

    mutating func append(_ row: BrowserDetailRow) {
        rows.append(row)
    }

    @discardableResult
    mutating func u8(_ offset: Int, _ key: String, format: (UInt8) -> String = { "\($0)" }) -> UInt8 {
        let value = reader.u8(at: offset) ?? 0
        field(offset, 1, key, format(value))
        return value
    }

    @discardableResult
    mutating func u16(_ offset: Int, _ key: String, format: (UInt16) -> String = { "\($0)" }) -> UInt16 {
        let value = reader.u16(at: offset, swapped: swapped) ?? 0
        field(offset, 2, key, format(value))
        return value
    }

    @discardableResult
    mutating func u32(_ offset: Int, _ key: String, format: (UInt32) -> String = { "\($0)" }) -> UInt32 {
        let value = reader.u32(at: offset, swapped: swapped) ?? 0
        field(offset, 4, key, format(value))
        return value
    }

    @discardableResult
    mutating func u64(_ offset: Int, _ key: String, format: (UInt64) -> String = { "\($0)" }) -> UInt64 {
        let value = reader.u64(at: offset, swapped: swapped) ?? 0
        field(offset, 8, key, format(value))
        return value
    }

    @discardableResult
    mutating func hex32(_ offset: Int, _ key: String) -> UInt32 {
        u32(offset, key, format: { hex($0) })
    }

    @discardableResult
    mutating func hex64(_ offset: Int, _ key: String) -> UInt64 {
        u64(offset, key, format: { hex($0) })
    }

    @discardableResult
    mutating func uleb(_ offset: Int, limit: Int, _ key: String, format: (UInt64) -> String = { "\($0)" }) -> (value: UInt64, length: Int) {
        guard let decoded = reader.uleb128(at: offset, limit: limit) else {
            append(offset, nil, key, "Invalid ULEB128")
            return (0, 1)
        }
        append(offset, reader.hexString(at: offset, count: decoded.length), key, format(decoded.value))
        return decoded
    }

    /// Continuation rows for each set flag, as MachOView lists them under a flags field.
    mutating func flags<T: FixedWidthInteger>(_ value: T, _ table: [(T, String)], width: Int = MemoryLayout<T>.size) {
        var remaining = value
        for (bit, name) in table where value & bit == bit && bit != 0 {
            note(padded(UInt64(bit), width: width), name)
            remaining &= ~bit
        }
        if remaining != 0 {
            note(padded(UInt64(remaining), width: width), "Unknown")
        }
    }

    func integerData(_ offset: Int, _ size: Int) -> String? {
        guard let value = reader.unsigned(at: offset, size: size, swapped: swapped) else { return nil }
        return padded(value, width: size)
    }
}

func hex<T: BinaryInteger>(_ value: T) -> String {
    "0x" + String(UInt64(truncatingIfNeeded: value), radix: 16, uppercase: true)
}

func padded(_ value: UInt64, width: Int) -> String {
    let digits = String(value, radix: 16, uppercase: true)
    let target = width * 2
    return digits.count >= target ? digits : String(repeating: "0", count: target - digits.count) + digits
}

func byteCount(_ value: UInt64) -> String {
    "\(value) (\(hex(value)))"
}

/// Shared factory for layout nodes; every node points at the original file's hex source.
struct LayoutNodeFactory {
    let hexSource: BrowserHexSource
    let rva: (Int) -> UInt64?

    func node(
        id: String,
        title: String,
        subtitle: String? = nil,
        summaryStyle: BrowserNodeSummaryStyle = .automatic,
        range: BrowserDataRange?,
        rvaAddress: UInt64? = nil,
        rows: @escaping () -> [BrowserDetailRow],
        children: [() -> BrowserNode] = []
    ) -> BrowserNode {
        BrowserNode(
            id: id,
            title: title,
            subtitle: subtitle,
            summaryStyle: summaryStyle,
            hexSource: hexSource,
            detailProvider: rows,
            childCount: children.count,
            indexedChildProvider: children.isEmpty ? nil : { children[$0]() },
            rawAddress: range.map { UInt64($0.offset) },
            rvaAddress: rvaAddress ?? range.flatMap { rva($0.offset) },
            dataRange: range
        )
    }

    func indexedNode(
        id: String,
        title: String,
        subtitle: String? = nil,
        range: BrowserDataRange?,
        rvaAddress: UInt64? = nil,
        rowCount: Int,
        row: @escaping (Int) -> BrowserDetailRow,
        childCount: Int = 0,
        child: ((Int) -> BrowserNode)? = nil
    ) -> BrowserNode {
        BrowserNode(
            id: id,
            title: title,
            subtitle: subtitle,
            hexSource: hexSource,
            detailCount: rowCount,
            indexedDetailProvider: row,
            childCount: childCount,
            indexedChildProvider: childCount > 0 ? child : nil,
            rawAddress: range.map { UInt64($0.offset) },
            rvaAddress: rvaAddress ?? range.flatMap { rva($0.offset) },
            dataRange: range
        )
    }
}

extension BrowserDataRange {
    init?(start: Int, length: Int, within limit: Int) {
        guard start >= 0, length > 0, start < limit else { return nil }
        self.init(offset: start, length: min(length, limit - start))
    }
}

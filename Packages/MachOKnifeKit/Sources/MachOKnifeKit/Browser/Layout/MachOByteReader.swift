import Foundation

/// Bounds-checked random access over a memory-mapped file.
///
/// Every offset is an absolute file offset. Reads never trap: out-of-range
/// accesses return `nil` so malformed binaries degrade into "invalid" rows
/// instead of crashing the browser.
final class MachOByteReader: @unchecked Sendable {
    let url: URL
    let data: Data

    var size: Int { data.count }

    init(url: URL) throws {
        self.url = url
        self.data = try Data(contentsOf: url, options: .alwaysMapped)
    }

    func contains(_ offset: Int, count: Int = 1) -> Bool {
        guard offset >= 0, count >= 0 else { return false }
        let (end, overflow) = offset.addingReportingOverflow(count)
        return overflow == false && end <= data.count
    }

    func bytes(at offset: Int, count: Int) -> Data? {
        guard contains(offset, count: count) else { return nil }
        return data.subdata(in: offset..<(offset + count))
    }

    func u8(at offset: Int) -> UInt8? {
        guard contains(offset) else { return nil }
        return data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in buffer[offset] }
    }

    func u16(at offset: Int, swapped: Bool = false) -> UInt16? {
        load(UInt16.self, at: offset).map { swapped ? $0.byteSwapped : $0 }
    }

    func u32(at offset: Int, swapped: Bool = false) -> UInt32? {
        load(UInt32.self, at: offset).map { swapped ? $0.byteSwapped : $0 }
    }

    func u64(at offset: Int, swapped: Bool = false) -> UInt64? {
        load(UInt64.self, at: offset).map { swapped ? $0.byteSwapped : $0 }
    }

    func u32BigEndian(at offset: Int) -> UInt32? {
        load(UInt32.self, at: offset).map { UInt32(bigEndian: $0) }
    }

    func u64BigEndian(at offset: Int) -> UInt64? {
        load(UInt64.self, at: offset).map { UInt64(bigEndian: $0) }
    }

    func u16BigEndian(at offset: Int) -> UInt16? {
        load(UInt16.self, at: offset).map { UInt16(bigEndian: $0) }
    }

    /// Unsigned integer of `size` bytes (1, 2, 4 or 8).
    func unsigned(at offset: Int, size: Int, swapped: Bool = false) -> UInt64? {
        switch size {
        case 1: return u8(at: offset).map(UInt64.init)
        case 2: return u16(at: offset, swapped: swapped).map(UInt64.init)
        case 4: return u32(at: offset, swapped: swapped).map(UInt64.init)
        case 8: return u64(at: offset, swapped: swapped)
        default: return nil
        }
    }

    /// Reads a NUL-terminated string starting at `offset`, scanning at most up to `limit` (exclusive).
    /// Returns the decoded string (lossy UTF-8) and the byte length excluding the terminator.
    func cString(at offset: Int, limit: Int? = nil) -> (string: String, length: Int)? {
        let end = min(limit ?? data.count, data.count)
        guard offset >= 0, offset < end else { return nil }
        return data.withUnsafeBytes { buffer -> (String, Int) in
            let base = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let available = end - offset
            let length: Int
            if let terminator = memchr(base + offset, 0, available) {
                length = UnsafeRawPointer(terminator) - UnsafeRawPointer(base + offset)
            } else {
                length = available
            }
            let bytes = UnsafeBufferPointer(start: base + offset, count: length)
            return (String(decoding: bytes, as: UTF8.self), length)
        }
    }

    /// Fixed-width, possibly non-terminated name field such as `segname[16]`.
    func fixedString(at offset: Int, count: Int) -> String? {
        guard let bytes = bytes(at: offset, count: count) else { return nil }
        let trimmed = bytes.prefix { $0 != 0 }
        return String(decoding: trimmed, as: UTF8.self)
    }

    func uleb128(at offset: Int, limit: Int) -> (value: UInt64, length: Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var cursor = offset
        let end = min(limit, data.count)
        while cursor < end {
            guard let byte = u8(at: cursor) else { return nil }
            cursor += 1
            if shift < 64 {
                result |= UInt64(byte & 0x7F) << shift
            }
            shift += 7
            if byte & 0x80 == 0 {
                return (result, cursor - offset)
            }
        }
        return nil
    }

    func sleb128(at offset: Int, limit: Int) -> (value: Int64, length: Int)? {
        var result: Int64 = 0
        var shift: Int64 = 0
        var cursor = offset
        var byte: UInt8 = 0
        let end = min(limit, data.count)
        repeat {
            guard cursor < end, let next = u8(at: cursor) else { return nil }
            byte = next
            cursor += 1
            if shift < 64 {
                result |= Int64(byte & 0x7F) << shift
            }
            shift += 7
        } while byte & 0x80 != 0
        if shift < 64, byte & 0x40 != 0 {
            result |= -(Int64(1) << shift)
        }
        return (result, cursor - offset)
    }

    func hexString(at offset: Int, count: Int, maximumBytes: Int = 16) -> String {
        let visible = min(count, maximumBytes)
        guard visible > 0, let bytes = bytes(at: offset, count: visible) else { return "" }
        let text = bytes.map { String(format: "%02X", $0) }.joined()
        return count > maximumBytes ? text + "…" : text
    }

    /// Finds offsets of every NUL-terminated string in `[start, end)`.
    func stringOffsets(from start: Int, to end: Int) -> [Int32] {
        let end = min(end, data.count)
        guard start >= 0, start < end else { return [] }
        var offsets: [Int32] = []
        data.withUnsafeBytes { buffer in
            let base = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            var cursor = start
            while cursor < end {
                offsets.append(Int32(truncatingIfNeeded: cursor - start))
                if let terminator = memchr(base + cursor, 0, end - cursor) {
                    cursor = UnsafeRawPointer(terminator) - UnsafeRawPointer(base) + 1
                } else {
                    cursor = end
                }
            }
        }
        return offsets
    }

    private func load<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T? {
        guard contains(offset, count: MemoryLayout<T>.size) else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
    }
}

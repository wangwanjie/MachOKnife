import Foundation
import MachO
import Testing
@testable import CoreMachO

/// 用手工构造的最小 Mach-O 覆盖解析器对不可信输入的边界处理。
struct ParserHardeningTests {
    @Test("fat headers with an absurd nfat_arch throw instead of allocating per entry")
    func hugeFatArchitectureCountThrows() throws {
        var data = Data()
        data.appendBigEndian(UInt32(FAT_MAGIC))
        data.appendBigEndian(UInt32.max)
        data.append(Data(count: 40))

        #expect(throws: MachOParseError.self) {
            _ = try MachOFileParser(data: data).parseContainer()
        }
        let url = try SyntheticMachO.write(data, name: "huge-nfat")
        #expect(throws: MachOParseError.self) {
            _ = try MachOMetadataScanner.scan(at: url)
        }
    }

    @Test("fat slices that are not Mach-O are rejected with unsupportedMagic")
    func nonMachOFatSliceIsRejected() throws {
        // 切片内容是 "!<arch>\n"：以前会被当作 32 位 Mach-O 头解析。
        let data = HardeningFixtures.fat64(offset: 64, size: 8)

        #expect {
            _ = try MachOFileParser(data: data).parseContainer()
        } throws: { error in
            guard case let .unsupportedMagic(magic)? = error as? MachOParseError else {
                return false
            }
            return magic == Data("!<ar".utf8).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        }
    }

    @Test("LC_BUILD_VERSION whose ntools exceeds cmdsize is rejected")
    func buildVersionToolCountIsBounded() throws {
        var command = Data()
        command.appendLittleEndian(UInt32(LC_BUILD_VERSION))
        command.appendLittleEndian(UInt32(24))
        command.appendLittleEndian(UInt32(1))
        command.appendLittleEndian(UInt32(0x000E_0000))
        command.appendLittleEndian(UInt32(0x000E_0000))
        command.appendLittleEndian(UInt32(0x1000_0000))
        let data = SyntheticMachO.make(commands: [command], trailing: Data(count: 64))

        #expect {
            _ = try MachOFileParser(data: data).parseContainer()
        } throws: { error in
            guard case .invalidLoadCommandSize(24)? = error as? MachOParseError else {
                return false
            }
            return true
        }
    }

    @Test("known load commands smaller than their structure are rejected")
    func undersizedKnownCommandIsRejected() throws {
        // LC_UUID 需要 24 字节，这里只给 8 字节；以前会越过命令读取后续数据当作 UUID。
        var command = Data()
        command.appendLittleEndian(UInt32(LC_UUID))
        command.appendLittleEndian(UInt32(8))
        let data = SyntheticMachO.make(commands: [command], trailing: Data(count: 64))

        #expect {
            _ = try MachOFileParser(data: data).parseContainer()
        } throws: { error in
            guard case .invalidLoadCommandSize(8)? = error as? MachOParseError else {
                return false
            }
            return true
        }
    }

    @Test("an absurd ncmds throws instead of reserving memory for every command")
    func hugeCommandCountThrows() throws {
        var data = SyntheticMachO.make(commands: [SyntheticMachO.rpathCommand("@loader_path")], trailing: Data(count: 16))
        data.writeLittleEndian(UInt32.max, at: 16)

        #expect(throws: MachOParseError.self) {
            _ = try MachOFileParser(data: data).parseContainer()
        }
    }

    @Test("the parser handles Data slices whose startIndex is not zero")
    func parserRebasesDataSlices() throws {
        let machO = SyntheticMachO.make(commands: [SyntheticMachO.rpathCommand("@loader_path/Frameworks")], trailing: Data(count: 16))
        let padded = Data([0xAA, 0xBB, 0xCC, 0xDD]) + machO
        let slice = padded[4...]
        #expect(slice.startIndex == 4)

        let container = try MachOFileParser(data: slice).parseContainer()
        #expect(container.slices.first?.rpaths == ["@loader_path/Frameworks"])
    }

    @Test("string-table batches advance by raw bytes even when names are not valid UTF-8")
    func stringTableBatchHandlesInvalidUTF8() throws {
        // 字符串表：[0] "" [1] 0xFF 0xFE 'A' [5] "B" [7] "C"
        let stringTable = Data([0x00, 0xFF, 0xFE, 0x41, 0x00, 0x42, 0x00, 0x43, 0x00])
        let fixture = try SyntheticMachO.symbolTableFixture(stringIndexes: [1, 5, 7], stringTable: stringTable)
        let scan = try MachOMetadataScanner.scan(at: fixture)
        let slice = try #require(scan.slices.first)

        let batch = try MachOStringTableBatchReader().readBatch(url: fixture, slice: slice, startIndex: 0, maximumCount: 10)

        #expect(batch.totalEntryCount == 4)
        #expect(batch.entries.map(\.stringTableIndex) == [0, 1, 5, 7])
        #expect(batch.entries.map(\.string) == ["", "\u{FFFD}\u{FFFD}A", "B", "C"])

        // 从中间开始读取时，条目序号与偏移依然一致。
        let tail = try MachOStringTableBatchReader().readBatch(url: fixture, slice: slice, startIndex: 2, maximumCount: 1)
        #expect(tail.entries.map(\.stringTableIndex) == [5])
        #expect(tail.entries.map(\.string) == ["B"])
    }

    @Test("string-table batches reject negative start indexes")
    func stringTableBatchRejectsNegativeStart() throws {
        let fixture = try SyntheticMachO.symbolTableFixture(stringIndexes: [1], stringTable: Data([0x00, 0x41, 0x00, 0x00]))
        let slice = try #require(try MachOMetadataScanner.scan(at: fixture).slices.first)

        #expect {
            _ = try MachOStringTableBatchReader().readBatch(url: fixture, slice: slice, startIndex: -1, maximumCount: 1)
        } throws: { error in
            guard case .startIndexOutOfBounds(-1, _)? = error as? MachOStringTableReaderError else {
                return false
            }
            return true
        }
    }

    @Test("symbol pages accept Int.max as maximumCount without overflowing")
    func symbolPageHandlesHugeMaximumCount() throws {
        let stringTable = Data([0x00]) + Data("_first".utf8) + Data([0x00]) + Data("_second".utf8) + Data([0x00])
        let fixture = try SyntheticMachO.symbolTableFixture(stringIndexes: [1, 8], stringTable: stringTable)
        let slice = try #require(try MachOMetadataScanner.scan(at: fixture).slices.first)

        let page = try MachOSymbolTablePageReader().readPage(url: fixture, slice: slice, startIndex: 1, maximumCount: Int.max)

        #expect(page.totalSymbolCount == 2)
        #expect(page.symbols.map(\.name) == ["_second"])
    }

    @Test("header-only CPU type detection matches the full parser")
    func sliceCPUTypesMatchFullParse() throws {
        let data = SyntheticMachO.make(commands: [SyntheticMachO.rpathCommand("@loader_path")], trailing: Data(count: 16))
        let types = try MachOFileParser(data: data).sliceCPUTypes()

        #expect(types.count == 1)
        #expect(types.first?.cpuType == CPU_TYPE_X86_64)
        #expect(types.first?.cpuSubtype == 3)
    }
}

/// 构造最小的 64 位小端 Mach-O（x86_64 / MH_DYLIB）。
enum SyntheticMachO {
    static let headerSize = 32

    static func make(commands: [Data], trailing: Data) -> Data {
        let commandBytes = commands.reduce(into: Data()) { $0.append($1) }
        var data = Data()
        data.appendLittleEndian(MH_MAGIC_64)
        data.appendLittleEndian(UInt32(bitPattern: CPU_TYPE_X86_64))
        data.appendLittleEndian(UInt32(3))
        data.appendLittleEndian(UInt32(MH_DYLIB))
        data.appendLittleEndian(UInt32(commands.count))
        data.appendLittleEndian(UInt32(commandBytes.count))
        data.appendLittleEndian(UInt32(0))
        data.appendLittleEndian(UInt32(0))
        data.append(commandBytes)
        data.append(trailing)
        return data
    }

    static func rpathCommand(_ path: String) -> Data {
        var pathBytes = Data(path.utf8) + Data([0])
        let size = (12 + pathBytes.count + 7) / 8 * 8
        pathBytes.append(Data(count: size - 12 - pathBytes.count))
        var command = Data()
        command.appendLittleEndian(UInt32(LC_RPATH))
        command.appendLittleEndian(UInt32(size))
        command.appendLittleEndian(UInt32(12))
        command.append(pathBytes)
        return command
    }

    /// 生成只含 LC_SYMTAB 的文件：每个符号是 nlist_64，n_strx 取自 `stringIndexes`。
    static func symbolTableFixture(stringIndexes: [UInt32], stringTable: Data) throws -> URL {
        let symbolOffset = headerSize + 24
        let stringOffset = symbolOffset + stringIndexes.count * 16

        var command = Data()
        command.appendLittleEndian(UInt32(LC_SYMTAB))
        command.appendLittleEndian(UInt32(24))
        command.appendLittleEndian(UInt32(symbolOffset))
        command.appendLittleEndian(UInt32(stringIndexes.count))
        command.appendLittleEndian(UInt32(stringOffset))
        command.appendLittleEndian(UInt32(stringTable.count))

        var payload = Data()
        for index in stringIndexes {
            payload.appendLittleEndian(index)
            payload.append(UInt8(N_SECT | N_EXT))
            payload.append(UInt8(1))
            payload.appendLittleEndian(UInt16(0))
            payload.appendLittleEndian(UInt64(0x1000))
        }
        payload.append(stringTable)

        return try write(make(commands: [command], trailing: payload), name: "symtab")
    }

    static func write(_ data: Data, name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyntheticMachO-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func writeLittleEndian<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        Swift.withUnsafeBytes(of: value.littleEndian) { rawBuffer in
            replaceSubrange((startIndex + offset)..<(startIndex + offset + rawBuffer.count), with: rawBuffer)
        }
    }

    func readLittleEndian<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        T(littleEndian: withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) })
    }

    func readBigEndian<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        T(bigEndian: withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) })
    }
}

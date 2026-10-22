import Foundation
import Testing
@testable import MachOKnifeKit

/// 畸形输入与惰性加载的回归测试：这些输入在修复前会让浏览器因整数溢出 / `Int(UInt64)` 转换直接崩溃，
/// 或在初次打开静态库时一次性解码整个符号表。
struct LayoutRobustnessTests {
    // MARK: Byte reader

    @Test("sleb128 sign-extends a 9-byte value without overflowing")
    func sleb128SignExtendsNineByteValue() throws {
        // 9 个字节后 shift == 63，旧实现执行 `-(1 << 63)` 会对 Int64.min 取负而崩溃。
        let reader = try LayoutBytes.reader(Data([0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x40, 0x7F, 0x80, 0x7F]))

        let nineBytes = try #require(reader.sleb128(at: 0, limit: 9))
        #expect(nineBytes.value == Int64(bitPattern: 0xC000_0000_0000_0000))
        #expect(nineBytes.length == 9)

        // 常规值保持原有语义：0x7F 为 -1，0x80 0x7F 为 -128。
        #expect(reader.sleb128(at: 9, limit: 10)?.value == -1)
        #expect(reader.sleb128(at: 10, limit: 12)?.value == -128)
    }

    @Test("offset arithmetic rejects deltas that do not fit in Int")
    func offsetArithmeticRejectsOverflow() {
        #expect(MachOByteReader.offset(16, adding: 32) == 48)
        #expect(MachOByteReader.offset(16, adding: UInt64.max) == nil)
        #expect(MachOByteReader.offset(Int.max - 1, adding: 2) == nil)
    }

    @Test("table size helpers saturate instead of trapping")
    func tableSizeHelpersSaturate() {
        #expect(saturatingTableSize(4, 16) == 64)
        #expect(saturatingTableSize(.max, 16) == .max)
        #expect(saturatingSum([1, 2, 3]) == 6)
        #expect(saturatingSum([.max, 1]) == .max)
        #expect(rangeContains(start: 10, length: 5, 14))
        #expect(rangeContains(start: 10, length: 5, 15) == false)
        #expect(rangeContains(start: .max - 1, length: .max, .max))
    }

    // MARK: Malformed images

    @Test("malformed counts, sizes and ULEB values degrade into rows instead of crashing")
    func malformedImageDoesNotCrash() throws {
        let url = try LayoutBytes.write(LayoutBytes.malformedImage())

        let document = try BrowserDocumentService().load(url: url)
        let root = try #require(document.rootNodes.first)
        LayoutBytes.visit(root)

        // 符号表行数按文件中实际存在的 nlist 条目截断：0x200..0x400 只容纳 32 个 16 字节条目。
        let symbols = try #require(root.children.first(where: { $0.title.hasPrefix("Symbol Table (") }))
        #expect(symbols.title == "Symbol Table (32)")
        #expect(symbols.detailCount == 32 * 5)
    }

    @Test("fat headers with 64-bit offsets beyond Int are rejected instead of crashing")
    func fat64OffsetsBeyondIntAreRejected() throws {
        var bytes = LayoutBytes()
        bytes.u32BE(0xCAFE_BABF)
        bytes.u32BE(1)
        bytes.u32BE(0x0100_000C)
        bytes.u32BE(0)
        bytes.u64BE(0xFFFF_FFFF_FFFF_FFF0)
        bytes.u64BE(0x10)
        bytes.u32BE(14)
        bytes.u32BE(0)
        bytes.pad(to: 0x100)
        let url = try LayoutBytes.write(bytes.data)

        #expect(throws: BrowserDocumentLoadError.self) {
            try BrowserDocumentService().load(url: url)
        }
    }

    @Test("files shorter than a dyld cache header are rejected instead of crashing inside MachOKit", arguments: [
        Data("not a binary".utf8),
        Data("dyld_v1  arm64e\0".utf8),
    ])
    func tinyFilesAreRejected(contents: Data) throws {
        // MachOKit 的 DyldCache(url:) 对短文件执行 try! 读取文件头，旧实现在这里直接崩溃。
        let url = try LayoutBytes.write(contents)

        #expect(BrowserDocumentService.mayBeDyldCache(url: url) == false)
        #expect(throws: BrowserDocumentLoadError.unsupportedFormat(url)) {
            try BrowserDocumentService().load(url: url)
        }
    }

    // MARK: Static archives

    @Test("opening a static library defers and pages its symbol table")
    func staticLibrarySymbolTableIsLazy() throws {
        let directory = try ToolFixtureFactory.makeDirectory()
        let first = try ToolFixtureFactory.compileObject(
            in: directory, name: "first", target: "x86_64-apple-macos13.0", body: "int first_fn(void) { return 1; }"
        )
        let second = try ToolFixtureFactory.compileObject(
            in: directory, name: "second", target: "x86_64-apple-macos13.0", body: "int second_fn(void) { return 2; }"
        )
        let archiveURL = directory.appendingPathComponent("libLazy.a")
        try ToolFixtureFactory.run("/usr/bin/libtool", arguments: ["-static", "-o", archiveURL.path, first.path, second.path])

        let document = try BrowserDocumentService().load(url: archiveURL)
        let root = try #require(document.rootNodes.first)
        // 初次打开只创建根节点，归档节点（及其符号表）尚未构建。
        #expect(root.loadedChildren.isEmpty)

        let archive = root.child(at: 0)
        #expect(archive.detailRows.contains(where: { $0.key == "Symbols" && $0.value == "2" }))
        #expect(archive.detailRows.contains(where: { $0.key == "Members" && $0.value == "2" }))

        let symbolTable = try #require(archive.children.first(where: { $0.title == "Symbol Table" }))
        #expect(symbolTable.detailCount == 1 + 2 * 2)
        #expect(symbolTable.loadedDetailRows.isEmpty)
        _ = symbolTable.detailRow(at: 1)
        // 只解码了被访问的那一行。
        #expect(symbolTable.loadedDetailRows.count == 1)

        let rows = (0..<symbolTable.detailCount).map(symbolTable.detailRow(at:))
        #expect(Set(rows.filter { $0.key == "String Offset" }.map(\.value)) == ["_first_fn", "_second_fn"])
        #expect(Set(rows.filter { $0.key == "Object Offset" }.map(\.value)) == ["first.o", "second.o"])
    }

    @Test("GNU archive symbol tables resolve names and owning members")
    func gnuArchiveSymbolTableResolvesNames() throws {
        // 手工构造 GNU 格式归档：符号表 "/"（大端计数 + 成员偏移 + NUL 分隔的名字）和一个普通成员。
        var symbolTable = LayoutBytes()
        symbolTable.u32BE(2)
        symbolTable.u32BE(88)
        symbolTable.u32BE(88)
        symbolTable.data.append(Data("foo\0bar\0".utf8))

        var bytes = LayoutBytes()
        bytes.data.append(Data("!<arch>\n".utf8))
        bytes.arHeader(name: "/", size: symbolTable.data.count)
        bytes.data.append(symbolTable.data)
        #expect(bytes.data.count == 88)
        bytes.arHeader(name: "a.o/", size: 6)
        bytes.data.append(Data("hello\n".utf8))
        let url = try LayoutBytes.write(bytes.data)

        let document = try BrowserDocumentService().load(url: url)
        let archive = try #require(document.rootNodes.first).child(at: 0)
        #expect(archive.detailRows.contains(where: { $0.key == "Symbols" && $0.value == "2" }))

        let table = try #require(archive.children.first(where: { $0.title == "Symbol Table" }))
        #expect(table.detailCount == 3)
        #expect(table.detailRow(at: 0).value == "2")
        #expect(table.detailRow(at: 1).key == "foo")
        #expect(table.detailRow(at: 1).value == "a.o")
        #expect(table.detailRow(at: 2).key == "bar")
        #expect(table.detailRow(at: 2).rawAddress == 8 + 60 + 8)
    }
}

/// 构造测试用二进制数据的小工具。
struct LayoutBytes {
    var data = Data()

    mutating func u32(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func u64(_ value: UInt64) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func u32BE(_ value: UInt32) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    mutating func u64BE(_ value: UInt64) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    mutating func name16(_ name: String) {
        var bytes = Array(name.utf8.prefix(16))
        bytes += Array(repeating: 0, count: 16 - bytes.count)
        data.append(contentsOf: bytes)
    }

    mutating func pad(to size: Int, byte: UInt8 = 0) {
        if data.count < size {
            data.append(Data(repeating: byte, count: size - data.count))
        }
    }

    /// 60 字节的 ar 成员头：名字、时间戳、uid、gid、mode、大小、结束标记。
    mutating func arHeader(name: String, size: Int) {
        func field(_ text: String, _ width: Int) -> String {
            text.padding(toLength: width, withPad: " ", startingAt: 0)
        }
        let header = field(name, 16) + field("0", 12) + field("0", 6) + field("0", 6) + field("644", 8) + field("\(size)", 10) + "`\n"
        data.append(Data(header.utf8))
    }

    static func write(_ data: Data) throws -> URL {
        let url = try ToolFixtureFactory.makeDirectory().appendingPathComponent("input.bin")
        try data.write(to: url)
        return url
    }

    static func reader(_ data: Data) throws -> MachOByteReader {
        try MachOByteReader(url: write(data))
    }

    /// 一个 x86_64 MH_EXECUTE：几乎所有计数/大小都是 0xFFFFFFFF，段地址加大小会溢出 UInt64，
    /// 导出 trie 的 terminal size 是超过 Int.max 的 ULEB128。
    static func malformedImage() -> Data {
        var bytes = LayoutBytes()
        // mach_header_64
        bytes.u32(0xFEED_FACF)
        bytes.u32(0x0100_0007)
        bytes.u32(3)
        bytes.u32(2)
        bytes.u32(4)
        bytes.u32(152 + 24 + 80 + 48)
        bytes.u32(0)
        bytes.u32(0)

        // LC_SEGMENT_64 + 一个 section_64
        bytes.u32(0x19)
        bytes.u32(152)
        bytes.name16("__TEXT")
        bytes.u64(0xFFFF_FFFF_FFFF_F000)
        bytes.u64(0x10000)
        bytes.u64(0)
        bytes.u64(0x400)
        bytes.u32(7)
        bytes.u32(5)
        bytes.u32(1)
        bytes.u32(0)
        bytes.name16("__text")
        bytes.name16("__TEXT")
        bytes.u64(0xFFFF_FFFF_FFFF_F000)
        bytes.u64(.max)
        bytes.u32(0x200)
        bytes.u32(0)
        bytes.u32(0x300)
        bytes.u32(.max)
        bytes.u32(0x8000_0400)
        bytes.u32(0)
        bytes.u32(0)
        bytes.u32(0)

        // LC_SYMTAB
        bytes.u32(0x2)
        bytes.u32(24)
        bytes.u32(0x200)
        bytes.u32(.max)
        bytes.u32(0x300)
        bytes.u32(0x100)

        // LC_DYSYMTAB：iextdefsym + nextdefsym 会溢出 UInt32。
        bytes.u32(0xB)
        bytes.u32(80)
        for value: UInt32 in [0, .max, 0xFFFF_FFF0, .max, 0, 0, 0x200, .max, 0x200, .max, 0x200, .max, 0x200, .max, 0x200, .max, 0x200, .max] {
            bytes.u32(value)
        }

        // LC_DYLD_INFO_ONLY：各段大小之和溢出 UInt32，导出信息指向畸形 trie。
        bytes.u32(0x8000_0022)
        bytes.u32(48)
        for value: UInt32 in [0x200, .max, 0x200, .max, 0x200, .max, 0x200, .max, 0x380, .max] {
            bytes.u32(value)
        }

        bytes.pad(to: 0x200)
        bytes.pad(to: 0x380, byte: 0xFF)
        // 导出 trie 根节点：terminal size = 2^64 - 1。
        bytes.data.append(contentsOf: Array(repeating: UInt8(0xFF), count: 9) + [0x01])
        bytes.pad(to: 0x400, byte: 0xFF)
        return bytes.data
    }

    /// 有界地遍历节点树，物化行和子节点，以触发所有惰性解码路径。
    static func visit(_ node: BrowserNode, depth: Int = 0) {
        guard depth < 6 else {
            return
        }
        let rowCount = node.detailCount
        for index in 0..<min(rowCount, 64) {
            _ = node.detailRow(at: index)
        }
        if rowCount > 0 {
            _ = node.detailRow(at: rowCount - 1)
        }
        for index in 0..<min(node.childCount, 32) {
            visit(node.child(at: index), depth: depth + 1)
        }
    }
}

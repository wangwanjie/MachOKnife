import Foundation
import MachO
import Testing
@testable import CoreMachO

struct ArchiveHardeningTests {
    @Test("written archives NUL-pad BSD names so payloads are 8-byte aligned and regenerate the TOC")
    func writtenArchivesAreAlignedAndLinkable() throws {
        let directory = try HardeningFixtures.makeDirectory()
        let firstObject = try HardeningFixtures.compileObject(
            source: "int hardening_first(void) { return 1; }\n",
            name: "first",
            in: directory
        )
        let secondObject = try HardeningFixtures.compileObject(
            source: "int hardening_second(void) { return 2; }\n",
            name: "second",
            in: directory
        )

        let archiveURL = directory.appendingPathComponent("libHardening.a")
        let inspector = ArchiveInspector()
        // Odd-length names and an odd-length payload exercise padding.
        try inspector.writeArchive(
            outputURL: archiveURL,
            members: [
                ArchiveMemberSource(name: "a.o", fileURL: firstObject),
                ArchiveMemberSource(name: "odd_name_1.o", fileURL: secondObject),
            ]
        )

        let layouts = try inspector.memberLayouts(in: archiveURL)
        #expect(layouts.map(\.name) == ["__.SYMDEF SORTED", "a.o", "odd_name_1.o"])
        for layout in layouts {
            #expect(layout.dataOffset % 8 == 0, "payload of \(layout.name) is not 8-byte aligned")
        }

        let data = try Data(contentsOf: archiveURL)
        // `#1/<len>` covers the padded name, and the name is NUL terminated.
        let firstObjectLayout = layouts[1]
        let header = String(decoding: data[firstObjectLayout.headerOffset..<(firstObjectLayout.headerOffset + 16)], as: UTF8.self)
        let nameLength = try #require(Int(header.trimmingCharacters(in: .whitespaces).dropFirst(3)))
        #expect(nameLength >= "a.o".utf8.count + 1)
        #expect(firstObjectLayout.dataOffset == firstObjectLayout.headerOffset + 60 + nameLength)
        #expect(data[firstObjectLayout.headerOffset + 60 + 3] == 0)

        // The table of contents points at the right member headers.
        let toc = try HardeningFixtures.parseTableOfContents(data: data, layout: layouts[0])
        #expect(toc["_hardening_first"] == layouts[1].headerOffset)
        #expect(toc["_hardening_second"] == layouts[2].headerOffset)

        // The linker accepts the archive and resolves symbols through the TOC.
        let mainSource = directory.appendingPathComponent("main.c")
        try "int hardening_second(void);\nint main(void) { return hardening_second() - 2; }\n"
            .write(to: mainSource, atomically: true, encoding: .utf8)
        try HardeningFixtures.run("/usr/bin/clang", [
            mainSource.path, archiveURL.path, "-o", directory.appendingPathComponent("main").path,
        ])
    }

    @Test("indexed extraction keeps duplicate member names and never escapes the destination")
    func indexedExtractionIsSafe() throws {
        let directory = try HardeningFixtures.makeDirectory()
        let payloadA = directory.appendingPathComponent("payloadA")
        let payloadB = directory.appendingPathComponent("payloadB")
        try Data("A".utf8).write(to: payloadA)
        try Data("BB".utf8).write(to: payloadB)

        let archiveURL = directory.appendingPathComponent("names.a")
        let inspector = ArchiveInspector()
        try inspector.writeArchive(
            outputURL: archiveURL,
            members: [
                ArchiveMemberSource(name: "dup.o", fileURL: payloadA),
                ArchiveMemberSource(name: "dup.o", fileURL: payloadB),
                ArchiveMemberSource(name: "../evil.o", fileURL: payloadA),
                ArchiveMemberSource(name: "..", fileURL: payloadA),
                ArchiveMemberSource(name: ".", fileURL: payloadB),
            ],
            generateSymbolTable: false
        )

        let destination = directory.appendingPathComponent("out", isDirectory: true)
        let extracted = try inspector.extractIndexedMembers(from: archiveURL, to: destination)

        #expect(extracted.map(\.name) == ["dup.o", "dup.o", "../evil.o", "..", "."])
        #expect(extracted.map(\.fileURL.lastPathComponent) == [
            "00000_dup.o", "00001_dup.o", "00002_.._evil.o", "00003_member", "00004_member",
        ])
        #expect(try Data(contentsOf: extracted[0].fileURL) == Data("A".utf8))
        #expect(try Data(contentsOf: extracted[1].fileURL) == Data("BB".utf8))
        for member in extracted {
            #expect(member.fileURL.deletingLastPathComponent().standardizedFileURL == destination.standardizedFileURL)
        }
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("evil.o").path) == false)

        // The legacy name-based API refuses traversal instead of writing outside the directory.
        #expect(throws: ArchiveInspectorError.self) {
            try inspector.extractMembers(from: archiveURL, to: directory.appendingPathComponent("legacy"))
        }

        // Rewriting from the indexed extraction keeps both duplicates and their original names.
        let rewrittenURL = directory.appendingPathComponent("rewritten.a")
        try inspector.writeArchive(
            outputURL: rewrittenURL,
            members: extracted.map { ArchiveMemberSource(name: $0.name, fileURL: $0.fileURL) },
            generateSymbolTable: false
        )
        #expect(try inspector.listMembers(in: rewrittenURL) == ["dup.o", "dup.o", "../evil.o", "..", "."])
    }

    @Test("malformed archive sizes and names throw instead of trapping", arguments: [
        HardeningFixtures.archive(name: "bad.o", sizeField: "-5", payload: Data()),
        HardeningFixtures.archive(name: "bad.o", sizeField: "99999999", payload: Data("x".utf8)),
        HardeningFixtures.archive(name: "bad.o", sizeField: "9999999999", payload: Data("x".utf8)),
        HardeningFixtures.archive(name: "bad.o", sizeField: "1x", payload: Data("xx".utf8)),
        HardeningFixtures.archive(name: "#1/-4", sizeField: "4", payload: Data("abcd".utf8)),
        HardeningFixtures.archive(name: "#1/8", sizeField: "4", payload: Data("abcd".utf8)),
        HardeningFixtures.archive(name: "/7", sizeField: "4", payload: Data("abcd".utf8)),
    ])
    func malformedArchivesThrow(data: Data) throws {
        let url = try HardeningFixtures.write(data, name: "malformed.a")
        #expect(throws: (any Error).self) {
            _ = try ArchiveInspector().listMembers(in: url)
        }
    }

    @Test("malformed fat headers throw instead of trapping", arguments: [
        // fat_arch_64 offset that does not fit in Int.
        HardeningFixtures.fat64(offset: UInt64.max - 15, size: 16),
        // offset + size overflows Int.
        HardeningFixtures.fat64(offset: UInt64(Int.max - 4), size: UInt64(Int.max - 4)),
        // size beyond the file.
        HardeningFixtures.fat64(offset: 64, size: 0xFFFF_FFFF),
    ])
    func malformedFatHeadersThrow(data: Data) throws {
        let url = try HardeningFixtures.write(data, name: "malformed-fat.a")
        #expect(throws: (any Error).self) {
            _ = try ArchiveInspector().inspect(url: url)
        }
        #expect(throws: (any Error).self) {
            _ = try MachOContainer.parse(at: url)
        }
    }

    @Test("resolves GNU ar long names from the // table")
    func resolvesGNULongNames() throws {
        let longName = "a_really_long_member_name_for_gnu.o"
        var data = Data("!<arch>\n".utf8)
        let table = Data("\(longName)/\nsecond_long_member_name_value.o/\n".utf8)
        data.append(HardeningFixtures.header(name: "//", size: table.count))
        data.append(table)
        if table.count % 2 == 1 { data.append(0x0A) }
        data.append(HardeningFixtures.header(name: "/0", size: 2))
        data.append(Data("AA".utf8))
        let secondOffset = longName.utf8.count + 2
        data.append(HardeningFixtures.header(name: "/\(secondOffset)", size: 2))
        data.append(Data("BB".utf8))
        data.append(HardeningFixtures.header(name: "short.o/", size: 2))
        data.append(Data("CC".utf8))

        let url = try HardeningFixtures.write(data, name: "gnu.a")
        let members = try ArchiveInspector().listMembers(in: url)

        #expect(members == ["//", longName, "second_long_member_name_value.o", "short.o"])
    }

    @Test("names x86_64h, arm64e and arm64_32 distinctly")
    func namesArchitectureVariants() {
        #expect(MachOArchitectureNaming.name(cpuType: CPU_TYPE_X86_64, cpuSubtype: 3) == "x86_64")
        #expect(MachOArchitectureNaming.name(cpuType: CPU_TYPE_X86_64, cpuSubtype: 8) == "x86_64h")
        #expect(MachOArchitectureNaming.name(cpuType: CPU_TYPE_ARM64, cpuSubtype: 0) == "arm64")
        #expect(MachOArchitectureNaming.name(cpuType: CPU_TYPE_ARM64, cpuSubtype: Int32(bitPattern: 0x8000_0002)) == "arm64e")
        #expect(MachOArchitectureNaming.name(cpuType: 0x0200_000C, cpuSubtype: 1) == "arm64_32")
    }

    @Test("version packing validates component ranges")
    func versionPackingValidatesRanges() throws {
        #expect(try MachOVersion(major: 14, minor: 2, patch: 1).packedValue() == 0x000E_0201)
        #expect(try MachOVersion(major: 0xFFFF, minor: 0xFF, patch: 0xFF).packedValue() == 0xFFFF_FFFF)
        #expect(throws: MachOVersionPackingError.self) { try MachOVersion(major: 0x1_0000, minor: 0, patch: 0).packedValue() }
        #expect(throws: MachOVersionPackingError.self) { try MachOVersion(major: 1, minor: 256, patch: 0).packedValue() }
        #expect(throws: MachOVersionPackingError.self) { try MachOVersion(major: 1, minor: 0, patch: -1).packedValue() }
    }
}

enum HardeningFixtures {
    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveHardening-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func write(_ data: Data, name: String) throws -> URL {
        let url = try makeDirectory().appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    static func compileObject(source: String, name: String, in directory: URL) throws -> URL {
        let sourceURL = directory.appendingPathComponent("\(name).c")
        let objectURL = directory.appendingPathComponent("\(name).o")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
        try run("/usr/bin/clang", ["-c", sourceURL.path, "-o", objectURL.path])
        return objectURL
    }

    static func header(name: String, size: Int) -> Data {
        func field(_ value: String, _ width: Int) -> String {
            value.padding(toLength: width, withPad: " ", startingAt: 0)
        }
        let text = field(name, 16) + field("0", 12) + field("0", 6) + field("0", 6) + field("644", 8) + field("\(size)", 10) + "`\n"
        return Data(text.utf8)
    }

    static func archive(name: String, sizeField: String, payload: Data) -> Data {
        func field(_ value: String, _ width: Int) -> String {
            value.padding(toLength: width, withPad: " ", startingAt: 0)
        }
        var data = Data("!<arch>\n".utf8)
        let text = field(name, 16) + field("0", 12) + field("0", 6) + field("0", 6) + field("644", 8) + field(sizeField, 10) + "`\n"
        data.append(Data(text.utf8))
        data.append(payload)
        return data
    }

    static func fat64(offset: UInt64, size: UInt64) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
        }
        append(UInt32(FAT_MAGIC_64))
        append(UInt32(1))
        append(UInt32(bitPattern: CPU_TYPE_ARM64))
        append(UInt32(0))
        append(offset)
        append(size)
        append(UInt32(3))
        append(UInt32(0))
        data.append(Data(count: 64 - data.count))
        data.append(Data("!<arch>\n".utf8))
        return data
    }

    static func parseTableOfContents(data: Data, layout: ArchiveMemberLayout) throws -> [String: Int] {
        func u32(_ offset: Int) -> Int {
            Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) })
        }
        let base = layout.dataOffset
        let rangesSize = u32(base)
        let stringSize = u32(base + 4 + rangesSize)
        let stringBase = base + 8 + rangesSize
        #expect(stringBase + stringSize == layout.dataOffset + layout.dataSize)

        var result = [String: Int]()
        for index in 0..<(rangesSize / 8) {
            let stringIndex = u32(base + 4 + index * 8)
            let memberOffset = u32(base + 8 + index * 8)
            let nameBytes = data[(stringBase + stringIndex)...].prefix(while: { $0 != 0 })
            result[String(decoding: nameBytes, as: UTF8.self)] = memberOffset
        }
        return result
    }

    static func run(_ launchPath: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw HardeningFixtureError.commandFailed("\(launchPath) \(arguments.joined(separator: " "))\n\(String(decoding: output, as: UTF8.self))")
        }
    }
}

enum HardeningFixtureError: Error {
    case commandFailed(String)
}

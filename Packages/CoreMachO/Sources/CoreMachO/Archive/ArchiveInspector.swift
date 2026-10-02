import CoreMachOC
import Foundation

public enum ArchiveContainerKind: Sendable {
    case archive
    case fatArchive
}

public struct ArchiveInspection: Sendable {
    public let fileURL: URL
    public let kind: ArchiveContainerKind
    public let architectures: [String]

    public init(fileURL: URL, kind: ArchiveContainerKind, architectures: [String]) {
        self.fileURL = fileURL
        self.kind = kind
        self.architectures = architectures
    }
}

public struct ThinArchiveExtraction: Sendable {
    public let architecture: String
    public let archiveURL: URL

    public init(architecture: String, archiveURL: URL) {
        self.architecture = architecture
        self.archiveURL = archiveURL
    }
}

public struct ArchiveMemberLayout: Sendable {
    public let name: String
    public let headerOffset: Int
    public let headerSize: Int
    public let dataOffset: Int
    public let dataSize: Int

    public init(
        name: String,
        headerOffset: Int,
        headerSize: Int,
        dataOffset: Int,
        dataSize: Int
    ) {
        self.name = name
        self.headerOffset = headerOffset
        self.headerSize = headerSize
        self.dataOffset = dataOffset
        self.dataSize = dataSize
    }
}

/// A member written by `ArchiveInspector.extractIndexedMembers(from:to:)`.
public struct ExtractedArchiveMember: Sendable, Equatable {
    /// Position of the member in the archive (symbol tables included).
    public let index: Int
    /// Original member name as stored in the archive.
    public let name: String
    /// Extracted file, named `<index>_<sanitized name>` so duplicate names never collide.
    public let fileURL: URL
    /// True for `__.SYMDEF*`, `/`, `/SYM64/` and `//` index members.
    public let isSymbolTable: Bool

    public init(index: Int, name: String, fileURL: URL, isSymbolTable: Bool) {
        self.index = index
        self.name = name
        self.fileURL = fileURL
        self.isSymbolTable = isSymbolTable
    }
}

/// A member to be written by `ArchiveInspector.writeArchive(outputURL:members:generateSymbolTable:)`.
public struct ArchiveMemberSource: Sendable, Equatable {
    /// Name stored in the archive header.
    public let name: String
    /// File providing the member contents.
    public let fileURL: URL

    public init(name: String, fileURL: URL) {
        self.name = name
        self.fileURL = fileURL
    }
}

public enum ArchiveInspectorError: LocalizedError {
    case architectureSelectionRequired([String])
    case architectureNotFound(String)
    case invalidArchive(URL)
    case invalidArchiveData(String)
    case unsupportedArchive(URL)

    public var errorDescription: String? {
        switch self {
        case let .architectureSelectionRequired(architectures):
            return "This archive contains multiple architectures: \(architectures.joined(separator: ", ")). Select one architecture first."
        case let .architectureNotFound(architecture):
            return "The archive does not contain the architecture \(architecture)."
        case let .invalidArchive(url):
            return "Invalid archive at \(url.path)."
        case let .invalidArchiveData(reason):
            return reason
        case let .unsupportedArchive(url):
            return "Unsupported archive format at \(url.path)."
        }
    }
}

public struct ArchiveInspector: Sendable {
    public init() {}

    public func inspect(url: URL) throws -> ArchiveInspection? {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])

        if isThinArchive(data: data) {
            let archive = try parseArchive(data: data)
            let architectures = archiveArchitectures(in: archive)
            return ArchiveInspection(
                fileURL: url,
                kind: .archive,
                architectures: architectures.isEmpty ? ["unknown"] : architectures
            )
        }

        guard isFatContainer(data: data) else {
            return nil
        }

        let slices = try parseFatArchiveSlices(data: data)
        guard slices.isEmpty == false else {
            return nil
        }

        guard slices.allSatisfy({ isThinArchive(data: $0.data) }) else {
            return nil
        }

        return ArchiveInspection(
            fileURL: url,
            kind: .fatArchive,
            architectures: slices.map(\.architecture)
        )
    }

    public func extractThinArchive(url: URL, preferredArchitecture: String? = nil) throws -> ThinArchiveExtraction {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let inspection = try inspect(url: url) else {
            throw ArchiveInspectorError.unsupportedArchive(url)
        }

        switch inspection.kind {
        case .archive:
            let architecture = preferredArchitecture ?? inspection.architectures.first ?? "unknown"
            if inspection.architectures.contains("unknown") == false,
               inspection.architectures.contains(architecture) == false {
                throw ArchiveInspectorError.architectureNotFound(architecture)
            }

            let archiveURL = try writeTemporaryArchive(
                data: data,
                fileName: url.lastPathComponent
            )
            return ThinArchiveExtraction(architecture: architecture, archiveURL: archiveURL)

        case .fatArchive:
            guard let preferredArchitecture else {
                throw ArchiveInspectorError.architectureSelectionRequired(inspection.architectures)
            }

            let slices = try parseFatArchiveSlices(data: data)
            guard let slice = slices.first(where: { $0.architecture == preferredArchitecture }) else {
                throw ArchiveInspectorError.architectureNotFound(preferredArchitecture)
            }

            let archiveURL = try writeTemporaryArchive(
                data: slice.data,
                fileName: "\(url.deletingPathExtension().lastPathComponent)-\(preferredArchitecture).a"
            )
            return ThinArchiveExtraction(architecture: preferredArchitecture, archiveURL: archiveURL)
        }
    }

    public func listMembers(in archiveURL: URL) throws -> [String] {
        let archive = try parseArchive(url: archiveURL)
        return archive.members.map(\.name)
    }

    public func memberLayouts(in archiveURL: URL) throws -> [ArchiveMemberLayout] {
        let archive = try parseArchive(url: archiveURL)
        return archive.members.map(\.layout)
    }

    /// Legacy extraction that writes each member to `directoryURL/<member name>`.
    ///
    /// Duplicate member names overwrite each other here, so new code should use
    /// `extractIndexedMembers(from:to:)`. Names that would escape `directoryURL`
    /// (absolute paths, `.`/`..` components) are rejected, and GNU symbol/name
    /// tables (`/`, `//`, `/SYM64/`) are not written.
    public func extractMembers(from archiveURL: URL, to directoryURL: URL) throws {
        let archive = try parseArchive(url: archiveURL)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let rootPath = directoryURL.standardizedFileURL.path

        for member in archive.members where Self.isGNUIndexMemberName(member.name) == false {
            let components = member.name.split(separator: "/", omittingEmptySubsequences: false)
            guard member.name.hasPrefix("/") == false,
                  components.allSatisfy({ $0.isEmpty == false && $0 != "." && $0 != ".." })
            else {
                throw ArchiveInspectorError.invalidArchiveData("Archive member name \"\(member.name)\" is not a safe file name.")
            }

            let destinationURL = directoryURL.appendingPathComponent(member.name).standardizedFileURL
            guard destinationURL.path.hasPrefix(rootPath + "/") else {
                throw ArchiveInspectorError.invalidArchiveData("Archive member name \"\(member.name)\" escapes the extraction directory.")
            }
            let parentDirectory = destinationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
            try member.data.write(to: destinationURL, options: [.atomic])
        }
    }

    /// Extracts every member to `directoryURL/<index>_<sanitized name>` so that duplicate
    /// member names (common in static archives) are all preserved and no member name can
    /// escape `directoryURL`. The returned list keeps the archive order and original names.
    @discardableResult
    public func extractIndexedMembers(from archiveURL: URL, to directoryURL: URL) throws -> [ExtractedArchiveMember] {
        let archive = try parseArchive(url: archiveURL)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        return try archive.members.enumerated().map { index, member in
            let fileURL = directoryURL.appendingPathComponent(Self.extractedFileName(index: index, memberName: member.name))
            try member.data.write(to: fileURL, options: [.atomic])
            return ExtractedArchiveMember(
                index: index,
                name: member.name,
                fileURL: fileURL,
                isSymbolTable: Self.isSymbolTableMemberName(member.name)
            )
        }
    }

    /// Returns true for archive index members: BSD `__.SYMDEF*` tables and the GNU
    /// `/`, `/SYM64/` symbol tables and `//` long-name table.
    public static func isSymbolTableMemberName(_ name: String) -> Bool {
        name.hasPrefix("__.SYMDEF") || isGNUIndexMemberName(name)
    }

    static func extractedFileName(index: Int, memberName: String) -> String {
        var sanitized = memberName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\0", with: "_")
        if sanitized.isEmpty || sanitized == "." || sanitized == ".." {
            sanitized = "member"
        }
        while sanitized.utf8.count > 200 {
            sanitized.removeLast()
        }
        let indexString = String(index)
        let paddedIndex = String(repeating: "0", count: max(0, 5 - indexString.count)) + indexString
        return "\(paddedIndex)_\(sanitized)"
    }

    private static func isGNUIndexMemberName(_ name: String) -> Bool {
        name == "/" || name == "//" || name == "/SYM64/"
    }

    public func writeArchive(
        outputURL: URL,
        memberNames: [String],
        sourceDirectoryURL: URL
    ) throws {
        try writeArchive(
            outputURL: outputURL,
            members: memberNames.map {
                ArchiveMemberSource(name: $0, fileURL: sourceDirectoryURL.appendingPathComponent($0))
            }
        )
    }

    /// Writes a BSD archive from `members` in order.
    ///
    /// Member names are stored with BSD `#1/<len>` extended names, NUL padded so that every
    /// member payload starts on an 8-byte boundary. When `generateSymbolTable` is true, any
    /// existing symbol tables in `members` are dropped and a fresh `__.SYMDEF SORTED` table of
    /// contents (equivalent to running `ranlib`) is generated from the members' defined
    /// external symbols, because member offsets change whenever the archive is rewritten.
    public func writeArchive(
        outputURL: URL,
        members: [ArchiveMemberSource],
        generateSymbolTable: Bool = true
    ) throws {
        var payloads = [(name: String, data: Data)]()
        payloads.reserveCapacity(members.count)
        for member in members {
            if generateSymbolTable, Self.isSymbolTableMemberName(member.name) {
                continue
            }
            payloads.append((member.name, try Data(contentsOf: member.fileURL, options: [.mappedIfSafe])))
        }

        let data = try makeArchiveData(members: payloads, generateSymbolTable: generateSymbolTable)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try data.write(to: outputURL, options: [.atomic])
    }

    /// Rebuilds the fat archive at `fatArchiveURL`, replacing the slice for `architecture` with
    /// the thin archive at `thinArchiveURL` and keeping every other slice unchanged.
    public func rebuildFatArchive(
        from fatArchiveURL: URL,
        replacingArchitecture architecture: String,
        withThinArchiveAt thinArchiveURL: URL,
        outputURL: URL
    ) throws {
        let fatData = try Data(contentsOf: fatArchiveURL, options: [.mappedIfSafe])
        let slices = try parseFatArchiveSlices(data: fatData)
        guard slices.contains(where: { $0.architecture == architecture }) else {
            throw ArchiveInspectorError.architectureNotFound(architecture)
        }

        let replacementData = try Data(contentsOf: thinArchiveURL, options: [.mappedIfSafe])
        guard isThinArchive(data: replacementData) else {
            throw ArchiveInspectorError.invalidArchiveData("The replacement slice for \(architecture) is not a static archive.")
        }

        let entries = slices.map { slice in
            (
                cpuType: slice.cpuType,
                cpuSubtype: slice.cpuSubtype,
                align: min(slice.align, 15),
                data: slice.architecture == architecture ? replacementData : slice.data
            )
        }

        let originalIs64Bit: Bool = {
            let magic = fatData.readUInt32(at: 0)
            return magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64
        }()

        func layout(is64Bit: Bool) -> (offsets: [Int], end: Int) {
            let entrySize = is64Bit ? 32 : 20
            var cursor = 8 + entries.count * entrySize
            var offsets = [Int]()
            for entry in entries {
                let alignment = 1 << Int(entry.align)
                cursor = (cursor + alignment - 1) / alignment * alignment
                offsets.append(cursor)
                cursor += entry.data.count
            }
            return (offsets, cursor)
        }

        var is64Bit = originalIs64Bit
        var placement = layout(is64Bit: is64Bit)
        if is64Bit == false,
           zip(placement.offsets, entries).contains(where: { $0 > Int(UInt32.max) || $1.data.count > Int(UInt32.max) }) {
            is64Bit = true
            placement = layout(is64Bit: true)
        }

        var output = Data()
        output.appendBigEndian(is64Bit ? FAT_MAGIC_64 : FAT_MAGIC)
        output.appendBigEndian(UInt32(entries.count))
        for (entry, offset) in zip(entries, placement.offsets) {
            output.appendBigEndian(UInt32(bitPattern: entry.cpuType))
            output.appendBigEndian(UInt32(bitPattern: entry.cpuSubtype))
            if is64Bit {
                output.appendBigEndian(UInt64(offset))
                output.appendBigEndian(UInt64(entry.data.count))
                output.appendBigEndian(entry.align)
                output.appendBigEndian(UInt32(0))
            } else {
                output.appendBigEndian(UInt32(offset))
                output.appendBigEndian(UInt32(entry.data.count))
                output.appendBigEndian(entry.align)
            }
        }
        for (entry, offset) in zip(entries, placement.offsets) {
            if output.count < offset {
                output.append(Data(count: offset - output.count))
            }
            output.append(entry.data)
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try output.write(to: outputURL, options: [.atomic])
    }

    private func parseArchive(url: URL) throws -> ParsedArchive {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try parseArchive(data: data)
    }

    private func parseArchive(data: Data) throws -> ParsedArchive {
        guard isThinArchive(data: data) else {
            throw ArchiveInspectorError.invalidArchiveData("The file is not a static archive.")
        }

        var members = [ArchiveMember]()
        var cursor = archiveMagic.utf8.count
        var gnuLongNameTable: Data?

        while cursor < data.count {
            // GNU ar may pad the final member; a lone trailing newline is not a header.
            guard data.count - cursor >= archiveHeaderSize else {
                if data.count - cursor == 1, data[data.startIndex + cursor] == 0x0A {
                    break
                }
                throw ArchiveInspectorError.invalidArchiveData("Archive member header is truncated.")
            }

            let headerRange = cursor..<(cursor + archiveHeaderSize)
            let header = data.subdata(in: headerRange)
            guard String(data: header.suffix(2), encoding: .ascii) == "`\n" else {
                throw ArchiveInspectorError.invalidArchiveData("Archive member terminator is invalid.")
            }

            let rawName = header.subdata(in: 0..<16).asciiString
            let sizeField = header.subdata(in: 48..<58).asciiString.trimmingCharacters(in: .whitespaces)
            guard sizeField.isEmpty == false,
                  sizeField.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let recordedSize = Int(sizeField)
            else {
                throw ArchiveInspectorError.invalidArchiveData("Archive member size \"\(sizeField)\" is invalid.")
            }

            let memberStart = cursor + archiveHeaderSize
            guard recordedSize <= data.count - memberStart else {
                throw ArchiveInspectorError.invalidArchiveData("Archive member data is truncated.")
            }
            let memberEnd = memberStart + recordedSize

            let memberStorage = data.subdata(in: memberStart..<memberEnd)
            let parsedMember = try parseArchiveMember(
                rawName: rawName,
                payload: memberStorage,
                headerOffset: cursor,
                dataOffset: memberStart,
                gnuLongNameTable: gnuLongNameTable
            )
            if parsedMember.name == "//" {
                gnuLongNameTable = parsedMember.data
            }
            members.append(parsedMember)

            cursor = memberEnd
            if recordedSize.isMultiple(of: 2) == false {
                cursor += 1
            }
        }

        return ParsedArchive(members: members)
    }

    private func parseArchiveMember(
        rawName: String,
        payload: Data,
        headerOffset: Int,
        dataOffset: Int,
        gnuLongNameTable: Data?
    ) throws -> ArchiveMember {
        let trimmedName = rawName.trimmingCharacters(in: .whitespaces)

        if trimmedName.hasPrefix("#1/") {
            let lengthField = trimmedName.dropFirst(3)
            guard lengthField.isEmpty == false,
                  lengthField.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let nameLength = Int(lengthField),
                  nameLength >= 0,
                  nameLength <= payload.count
            else {
                throw ArchiveInspectorError.invalidArchiveData("Archive member name is invalid.")
            }

            let nameData = payload.prefix(nameLength)
            let name = String(decoding: nameData.prefix(while: { $0 != 0 }), as: UTF8.self)
            let resolvedName = name.isEmpty ? "unknown" : name
            return ArchiveMember(
                name: resolvedName,
                data: Data(payload.dropFirst(nameLength)),
                layout: ArchiveMemberLayout(
                    name: resolvedName,
                    headerOffset: headerOffset,
                    headerSize: archiveHeaderSize,
                    dataOffset: dataOffset + nameLength,
                    dataSize: payload.count - nameLength
                )
            )
        }

        let resolvedName: String
        switch trimmedName {
        case "/", "//", "/SYM64/":
            resolvedName = trimmedName
        default:
            if trimmedName.hasPrefix("/"),
               trimmedName.count > 1,
               trimmedName.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber }) {
                resolvedName = try resolveGNULongName(reference: trimmedName.dropFirst(), table: gnuLongNameTable)
            } else {
                // GNU short names are terminated with "/"; BSD short names are space padded.
                var name = trimmedName
                if name.hasSuffix("/") {
                    name.removeLast()
                }
                resolvedName = name.isEmpty ? "unknown" : name
            }
        }

        return ArchiveMember(
            name: resolvedName,
            data: payload,
            layout: ArchiveMemberLayout(
                name: resolvedName,
                headerOffset: headerOffset,
                headerSize: archiveHeaderSize,
                dataOffset: dataOffset,
                dataSize: payload.count
            )
        )
    }

    private func resolveGNULongName(reference: Substring, table: Data?) throws -> String {
        guard let table else {
            throw ArchiveInspectorError.invalidArchiveData("Archive member references a GNU long name but the archive has no \"//\" name table.")
        }
        guard let offset = Int(reference), offset >= 0, offset < table.count else {
            throw ArchiveInspectorError.invalidArchiveData("Archive member GNU long name offset /\(reference) is out of bounds.")
        }

        let bytes = table.dropFirst(offset).prefix(while: { $0 != 0x0A && $0 != 0 })
        var name = String(decoding: bytes, as: UTF8.self)
        if name.hasSuffix("/") {
            name.removeLast()
        }
        guard name.isEmpty == false else {
            throw ArchiveInspectorError.invalidArchiveData("Archive member GNU long name at offset /\(reference) is empty.")
        }
        return name
    }

    private func isThinArchive(data: Data) -> Bool {
        data.starts(with: Data(archiveMagic.utf8))
    }

    private func isFatContainer(data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        let magic = data.readUInt32(at: 0)
        return magic == FAT_MAGIC || magic == FAT_CIGAM || magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64
    }

    private func parseFatArchiveSlices(data: Data) throws -> [FatArchiveSlice] {
        guard isFatContainer(data: data) else {
            throw ArchiveInspectorError.invalidArchiveData("The file is not a fat archive container.")
        }

        let magic = data.readUInt32(at: 0)
        let swapped = magic == FAT_CIGAM || magic == FAT_CIGAM_64
        let is64Bit = magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64
        let architectureCount = Int(data.readUInt32(at: 4, swapped: swapped))
        let architectureHeaderSize = is64Bit ? MemoryLayout<fat_arch_64>.size : MemoryLayout<fat_arch>.size
        let architecturesStart = MemoryLayout<fat_header>.size

        guard architectureCount <= (data.count - architecturesStart) / architectureHeaderSize else {
            throw ArchiveInspectorError.invalidArchiveData("The fat archive header is truncated.")
        }

        return try (0..<architectureCount).map { index in
            let entryOffset = architecturesStart + index * architectureHeaderSize
            guard entryOffset + architectureHeaderSize <= data.count else {
                throw ArchiveInspectorError.invalidArchiveData("The fat archive header is truncated.")
            }

            let cpuType = Int32(bitPattern: data.readUInt32(at: entryOffset, swapped: swapped))
            let cpuSubtype = Int32(bitPattern: data.readUInt32(at: entryOffset + 4, swapped: swapped))
            let rawOffset: UInt64
            let rawSize: UInt64
            let align: UInt32

            if is64Bit {
                rawOffset = data.readUInt64(at: entryOffset + 8, swapped: swapped)
                rawSize = data.readUInt64(at: entryOffset + 16, swapped: swapped)
                align = data.readUInt32(at: entryOffset + 24, swapped: swapped)
            } else {
                rawOffset = UInt64(data.readUInt32(at: entryOffset + 8, swapped: swapped))
                rawSize = UInt64(data.readUInt32(at: entryOffset + 12, swapped: swapped))
                align = data.readUInt32(at: entryOffset + 16, swapped: swapped)
            }

            guard let sliceOffset = Int(exactly: rawOffset),
                  let sliceSize = Int(exactly: rawSize),
                  case let (sliceEnd, overflow) = sliceOffset.addingReportingOverflow(sliceSize),
                  overflow == false,
                  sliceEnd <= data.count
            else {
                throw ArchiveInspectorError.invalidArchiveData("A fat archive slice is out of bounds.")
            }

            let sliceData = data.subdata(in: sliceOffset..<sliceEnd)
            return FatArchiveSlice(
                architecture: architectureName(cpuType: cpuType, cpuSubtype: cpuSubtype),
                cpuType: cpuType,
                cpuSubtype: cpuSubtype,
                align: align,
                data: sliceData
            )
        }
    }

    private func archiveArchitectures(in archive: ParsedArchive) -> [String] {
        var architectures = [String]()

        for member in archive.members {
            guard let memberArchitectures = try? machOArchitectures(in: member.data) else {
                continue
            }

            for architecture in memberArchitectures where architectures.contains(architecture) == false {
                architectures.append(architecture)
            }
        }

        return architectures
    }

    private func machOArchitectures(in data: Data) throws -> [String] {
        let container = try MachOFileParser(data: data).parseContainer()
        return container.slices.reduce(into: [String]()) { architectures, slice in
            let architecture = architectureName(
                cpuType: slice.header.cpuType,
                cpuSubtype: slice.header.cpuSubtype
            )
            if architectures.contains(architecture) == false {
                architectures.append(architecture)
            }
        }
    }

    private func architectureName(cpuType: Int32, cpuSubtype: Int32) -> String {
        MachOArchitectureNaming.name(cpuType: cpuType, cpuSubtype: cpuSubtype)
    }

    private func writeTemporaryArchive(data: Data, fileName: String) throws -> URL {
        let outputURL = try temporaryDirectory().appendingPathComponent(fileName)
        try data.write(to: outputURL, options: [.atomic])
        return outputURL
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MachOKnifeArchive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Archive writing

    private func makeArchiveData(members: [(name: String, data: Data)], generateSymbolTable: Bool) throws -> Data {
        let magicData = Data(archiveMagic.utf8)

        guard generateSymbolTable,
              let tableOfContents = makeTableOfContentsPlan(members: members)
        else {
            var data = magicData
            for member in members {
                data.append(makeArchiveMember(named: member.name, data: member.data, absoluteOffset: data.count))
            }
            return data
        }

        // The table of contents is the first member, and its size only depends on the symbol
        // names, so reserve its space first and fill it once member offsets are known.
        let tocMemberSize = makeArchiveMember(
            named: tableOfContents.memberName,
            data: Data(count: tableOfContents.payloadSize),
            absoluteOffset: magicData.count
        ).count

        var data = magicData
        data.append(Data(count: tocMemberSize))
        var memberHeaderOffsets = [Int]()
        for member in members {
            memberHeaderOffsets.append(data.count)
            data.append(makeArchiveMember(named: member.name, data: member.data, absoluteOffset: data.count))
        }

        guard memberHeaderOffsets.allSatisfy({ $0 <= Int(UInt32.max) }) else {
            // Offsets do not fit a 32-bit __.SYMDEF; write the archive without a table of contents.
            return try makeArchiveData(members: members, generateSymbolTable: false)
        }

        var payload = Data()
        payload.appendLittleEndian(UInt32(tableOfContents.entries.count * 8))
        for entry in tableOfContents.entries {
            payload.appendLittleEndian(UInt32(entry.stringOffset))
            payload.appendLittleEndian(UInt32(memberHeaderOffsets[entry.memberIndex]))
        }
        payload.appendLittleEndian(UInt32(tableOfContents.stringTable.count))
        payload.append(tableOfContents.stringTable)

        let tocMember = makeArchiveMember(
            named: tableOfContents.memberName,
            data: payload,
            absoluteOffset: magicData.count
        )
        precondition(tocMember.count == tocMemberSize, "table of contents size changed while writing")
        data.replaceSubrange(magicData.count..<(magicData.count + tocMemberSize), with: tocMember)
        return data
    }

    private struct TableOfContentsPlan {
        struct Entry {
            let stringOffset: Int
            let memberIndex: Int
        }

        let memberName: String
        let entries: [Entry]
        let stringTable: Data

        var payloadSize: Int {
            4 + entries.count * 8 + 4 + stringTable.count
        }
    }

    /// Mirrors `ranlib`: collects defined external symbols of every Mach-O object member.
    /// Returns nil when no member is a Mach-O object (for example an archive of bitcode or
    /// resources), in which case no table of contents is written.
    private func makeTableOfContentsPlan(members: [(name: String, data: Data)]) -> TableOfContentsPlan? {
        var symbols = [(name: [UInt8], memberIndex: Int)]()
        var sawObjectMember = false

        for (index, member) in members.enumerated() {
            guard let memberSymbols = Self.definedExternalSymbols(inObject: member.data) else {
                continue
            }
            sawObjectMember = true
            symbols.append(contentsOf: memberSymbols.map { ($0, index) })
        }

        guard sawObjectMember else {
            return nil
        }

        // Like libtool, only emit a sorted table when every symbol is defined once.
        let isUnique = Set(symbols.map(\.name)).count == symbols.count
        if isUnique {
            symbols.sort { $0.name.lexicographicallyPrecedes($1.name) }
        }

        var stringTable = Data()
        var entries = [TableOfContentsPlan.Entry]()
        entries.reserveCapacity(symbols.count)
        for symbol in symbols {
            entries.append(.init(stringOffset: stringTable.count, memberIndex: symbol.memberIndex))
            stringTable.append(contentsOf: symbol.name)
            stringTable.append(0)
        }
        let paddedStringTableSize = (stringTable.count + 7) / 8 * 8
        stringTable.append(Data(count: paddedStringTableSize - stringTable.count))

        return TableOfContentsPlan(
            memberName: isUnique ? "__.SYMDEF SORTED" : "__.SYMDEF",
            entries: entries,
            stringTable: stringTable
        )
    }

    /// Returns the defined external symbol names of a thin Mach-O object, or nil when `data`
    /// is not a thin Mach-O file.
    static func definedExternalSymbols(inObject data: Data) -> [[UInt8]]? {
        let data = Data(data)
        guard data.count >= 28 else { return nil }

        let magic = data.readUInt32(at: 0)
        let is64Bit: Bool
        let swapped: Bool
        switch magic {
        case MH_MAGIC: (is64Bit, swapped) = (false, false)
        case MH_CIGAM: (is64Bit, swapped) = (false, true)
        case MH_MAGIC_64: (is64Bit, swapped) = (true, false)
        case MH_CIGAM_64: (is64Bit, swapped) = (true, true)
        default: return nil
        }

        let headerSize = is64Bit ? 32 : 28
        guard data.count >= headerSize else { return nil }
        let commandCount = Int(data.readUInt32(at: 16, swapped: swapped))

        var cursor = headerSize
        for _ in 0..<commandCount {
            guard cursor + 8 <= data.count else { return [] }
            let command = data.readUInt32(at: cursor, swapped: swapped)
            let commandSize = Int(data.readUInt32(at: cursor + 4, swapped: swapped))
            guard commandSize >= 8, commandSize <= data.count - cursor else { return [] }
            defer { cursor += commandSize }

            guard command == UInt32(LC_SYMTAB), commandSize >= 24 else { continue }
            let symbolOffset = Int(data.readUInt32(at: cursor + 8, swapped: swapped))
            let symbolCount = Int(data.readUInt32(at: cursor + 12, swapped: swapped))
            let stringOffset = Int(data.readUInt32(at: cursor + 16, swapped: swapped))
            let stringSize = Int(data.readUInt32(at: cursor + 20, swapped: swapped))
            let entrySize = is64Bit ? 16 : 12

            guard symbolOffset + symbolCount * entrySize <= data.count,
                  stringOffset + stringSize <= data.count
            else {
                return []
            }

            var names = [[UInt8]]()
            for index in 0..<symbolCount {
                let entry = symbolOffset + index * entrySize
                let stringIndex = Int(data.readUInt32(at: entry, swapped: swapped))
                let type = data[data.startIndex + entry + 4]
                let value = is64Bit
                    ? data.readUInt64(at: entry + 8, swapped: swapped)
                    : UInt64(data.readUInt32(at: entry + 8, swapped: swapped))

                let isDebug = type & UInt8(N_STAB) != 0
                let isExternal = type & UInt8(N_EXT) != 0
                let isUndefined = type & UInt8(N_TYPE) == UInt8(N_UNDF)
                guard isDebug == false, isExternal, isUndefined == false || value != 0 else { continue }
                guard stringIndex > 0, stringIndex < stringSize else { continue }

                let start = data.startIndex + stringOffset + stringIndex
                let end = data.startIndex + stringOffset + stringSize
                let name = Array(data[start..<end].prefix(while: { $0 != 0 }))
                if name.isEmpty == false {
                    names.append(name)
                }
            }
            return names
        }

        return []
    }

    /// Serializes one BSD archive member whose header starts at `absoluteOffset` in the archive.
    ///
    /// Names are always stored as `#1/<len>` extended names; the stored name is NUL terminated
    /// and padded so that the member payload begins on an 8-byte boundary, which is what
    /// ld64/libtool expect. `ar_size` covers the padded name plus the payload, and an odd
    /// member is followed by a `\n` pad byte.
    private func makeArchiveMember(named name: String, data memberData: Data, absoluteOffset: Int) -> Data {
        let nameBytes = Data(name.utf8)
        var paddedNameLength = nameBytes.count + 1
        while (absoluteOffset + archiveHeaderSize + paddedNameLength) % 8 != 0 {
            paddedNameLength += 1
        }
        let storedSize = paddedNameLength + memberData.count

        var member = Data()
        member.append(paddedASCII("#1/\(paddedNameLength)", width: 16))
        member.append(paddedASCII("0", width: 12))
        member.append(paddedASCII("0", width: 6))
        member.append(paddedASCII("0", width: 6))
        member.append(paddedASCII("100644", width: 8))
        member.append(paddedASCII("\(storedSize)", width: 10))
        member.append(Data("`\n".utf8))
        member.append(nameBytes)
        member.append(Data(count: paddedNameLength - nameBytes.count))
        member.append(memberData)

        if storedSize.isMultiple(of: 2) == false {
            member.append(0x0A)
        }
        return member
    }

    private func paddedASCII(_ value: String, width: Int) -> Data {
        let truncated = String(value.prefix(width))
        let padded = truncated.padding(toLength: width, withPad: " ", startingAt: 0)
        return Data(padded.utf8)
    }
}

private let archiveMagic = "!<arch>\n"
private let archiveHeaderSize = 60

private struct ParsedArchive {
    let members: [ArchiveMember]
}

private struct ArchiveMember {
    let name: String
    let data: Data
    let layout: ArchiveMemberLayout
}

private struct FatArchiveSlice {
    let architecture: String
    let cpuType: Int32
    let cpuSubtype: Int32
    let align: UInt32
    let data: Data
}

private extension Data {
    func readUInt32(at offset: Int, swapped: Bool = false) -> UInt32 {
        let value = withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        return swapped ? value.byteSwapped : value
    }

    func readUInt64(at offset: Int, swapped: Bool = false) -> UInt64 {
        let value = withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
        }
        return swapped ? value.byteSwapped : value
    }

    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    var asciiString: String {
        String(decoding: self, as: UTF8.self)
    }
}

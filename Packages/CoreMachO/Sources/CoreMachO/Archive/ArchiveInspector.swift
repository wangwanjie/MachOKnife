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

    public func extractMembers(from archiveURL: URL, to directoryURL: URL) throws {
        let archive = try parseArchive(url: archiveURL)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        for member in archive.members {
            let destinationURL = directoryURL.appendingPathComponent(member.name)
            let parentDirectory = destinationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
            try member.data.write(to: destinationURL, options: [.atomic])
        }
    }

    public func writeArchive(
        outputURL: URL,
        memberNames: [String],
        sourceDirectoryURL: URL
    ) throws {
        var data = Data(archiveMagic.utf8)

        for name in memberNames {
            let memberURL = sourceDirectoryURL.appendingPathComponent(name)
            let memberData = try Data(contentsOf: memberURL, options: [.mappedIfSafe])
            appendArchiveMember(named: name, data: memberData, to: &data)
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try data.write(to: outputURL, options: [.atomic])
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

        while cursor < data.count {
            guard cursor + archiveHeaderSize <= data.count else {
                throw ArchiveInspectorError.invalidArchiveData("Archive member header is truncated.")
            }

            let headerRange = cursor..<(cursor + archiveHeaderSize)
            let header = data.subdata(in: headerRange)
            guard String(data: header.suffix(2), encoding: .ascii) == "`\n" else {
                throw ArchiveInspectorError.invalidArchiveData("Archive member terminator is invalid.")
            }

            let rawName = header.subdata(in: 0..<16).asciiString
            let sizeField = header.subdata(in: 48..<58).asciiString
            guard let recordedSize = Int(sizeField.trimmingCharacters(in: .whitespaces)) else {
                throw ArchiveInspectorError.invalidArchiveData("Archive member size is invalid.")
            }

            let memberStart = cursor + archiveHeaderSize
            let memberEnd = memberStart + recordedSize
            guard memberEnd <= data.count else {
                throw ArchiveInspectorError.invalidArchiveData("Archive member data is truncated.")
            }

            let memberStorage = data.subdata(in: memberStart..<memberEnd)
            let parsedMember = try parseArchiveMember(
                rawName: rawName,
                payload: memberStorage,
                headerOffset: cursor,
                dataOffset: memberStart
            )
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
        dataOffset: Int
    ) throws -> ArchiveMember {
        let trimmedName = rawName.trimmingCharacters(in: .whitespaces)

        if trimmedName.hasPrefix("#1/") {
            guard let nameLength = Int(trimmedName.dropFirst(3)), nameLength <= payload.count else {
                throw ArchiveInspectorError.invalidArchiveData("Archive member name is invalid.")
            }

            let nameData = payload.prefix(nameLength)
            let name = String(data: nameData, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                ?? "unknown"
            return ArchiveMember(
                name: name,
                data: payload.dropFirst(nameLength),
                layout: ArchiveMemberLayout(
                    name: name,
                    headerOffset: headerOffset,
                    headerSize: archiveHeaderSize,
                    dataOffset: dataOffset + nameLength,
                    dataSize: payload.count - nameLength
                )
            )
        }

        let normalizedName: String
        switch trimmedName {
        case "/", "//":
            normalizedName = trimmedName
        default:
            normalizedName = trimmedName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        let resolvedName = normalizedName.isEmpty ? "unknown" : normalizedName
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

    private func isThinArchive(data: Data) -> Bool {
        data.starts(with: Data(archiveMagic.utf8))
    }

    private func isFatContainer(data: Data) -> Bool {
        guard data.count >= 4 else { return false }
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

        return try (0..<architectureCount).map { index in
            let entryOffset = architecturesStart + index * architectureHeaderSize
            guard entryOffset + architectureHeaderSize <= data.count else {
                throw ArchiveInspectorError.invalidArchiveData("The fat archive header is truncated.")
            }

            let cpuType: Int32
            let cpuSubtype: Int32
            let sliceOffset: Int
            let sliceSize: Int

            if is64Bit {
                cpuType = Int32(bitPattern: data.readUInt32(at: entryOffset, swapped: swapped))
                cpuSubtype = Int32(bitPattern: data.readUInt32(at: entryOffset + 4, swapped: swapped))
                sliceOffset = Int(data.readUInt64(at: entryOffset + 8, swapped: swapped))
                sliceSize = Int(data.readUInt64(at: entryOffset + 16, swapped: swapped))
            } else {
                cpuType = Int32(bitPattern: data.readUInt32(at: entryOffset, swapped: swapped))
                cpuSubtype = Int32(bitPattern: data.readUInt32(at: entryOffset + 4, swapped: swapped))
                sliceOffset = Int(data.readUInt32(at: entryOffset + 8, swapped: swapped))
                sliceSize = Int(data.readUInt32(at: entryOffset + 12, swapped: swapped))
            }

            guard sliceOffset >= 0, sliceSize >= 0, sliceOffset + sliceSize <= data.count else {
                throw ArchiveInspectorError.invalidArchiveData("A fat archive slice is out of bounds.")
            }

            let sliceData = data.subdata(in: sliceOffset..<(sliceOffset + sliceSize))
            return FatArchiveSlice(
                architecture: architectureName(cpuType: cpuType, cpuSubtype: cpuSubtype),
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
        let subtype = cpuSubtype & 0x00FF_FFFF

        switch cpuType {
        case CPU_TYPE_ARM64:
            return subtype == 2 ? "arm64e" : "arm64"
        case CPU_TYPE_X86_64:
            return "x86_64"
        case CPU_TYPE_ARM:
            switch subtype {
            case 6: return "armv6"
            case 9: return "armv7"
            case 10: return "armv7f"
            case 11: return "armv7s"
            case 12: return "armv7k"
            default: return "arm"
            }
        case CPU_TYPE_X86:
            return "i386"
        case CPU_TYPE_POWERPC:
            return "ppc"
        case CPU_TYPE_POWERPC64:
            return "ppc64"
        default:
            return "cputype_\(cpuType)_subtype_\(subtype)"
        }
    }

    private func writeTemporaryArchive(data: Data, fileName: String) throws -> URL {
        let outputURL = temporaryDirectory().appendingPathComponent(fileName)
        try data.write(to: outputURL, options: [.atomic])
        return outputURL
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MachOKnifeArchive-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func appendArchiveMember(named name: String, data memberData: Data, to archiveData: inout Data) {
        let nameData = Data(name.utf8)
        let headerName = "#1/\(nameData.count)"
        let storedSize = nameData.count + memberData.count

        archiveData.append(paddedASCII(headerName, width: 16))
        archiveData.append(paddedASCII("0", width: 12))
        archiveData.append(paddedASCII("0", width: 6))
        archiveData.append(paddedASCII("0", width: 6))
        archiveData.append(paddedASCII("100644", width: 8))
        archiveData.append(paddedASCII("\(storedSize)", width: 10))
        archiveData.append(Data("`\n".utf8))
        archiveData.append(nameData)
        archiveData.append(memberData)

        if storedSize.isMultiple(of: 2) == false {
            archiveData.append(0x0A)
        }
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

    var asciiString: String {
        String(decoding: self, as: UTF8.self)
    }
}

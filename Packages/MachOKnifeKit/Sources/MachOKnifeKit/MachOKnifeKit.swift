import CoreMachO
import Foundation

public struct DocumentAnalysis: Sendable {
    public let fileURL: URL
    public let containerKind: MachOContainer.Kind
    public let slices: [SliceSummary]
}

public struct SliceSummary: Sendable {
    public let fileOffset: Int
    public let is64Bit: Bool
    public let header: HeaderSummary
    public let loadCommandCount: Int
    public let loadCommands: [LoadCommandSummary]
    public let platform: MachOPlatform?
    public let minimumOS: MachOVersion?
    public let sdkVersion: MachOVersion?
    public let installName: String?
    public let dylibReferences: [DylibSummary]
    public let rpaths: [String]
    public let segments: [SegmentSummary]
    public let symbols: [SymbolSummary]
    public let uuid: UUID?
    public let hasCodeSignature: Bool
    public let codeSignature: LinkEditDataSummary?
    public let encryptionInfo: EncryptionSummary?
}

public struct HeaderSummary: Sendable {
    public let cpuType: Int32
    public let cpuSubtype: Int32
    public let fileType: UInt32
    public let numberOfCommands: UInt32
    public let sizeofCommands: UInt32
    public let flags: UInt32
    public let reserved: UInt32?
}

public struct LoadCommandSummary: Sendable {
    public let command: UInt32
    public let size: UInt32
    public let offset: Int
    public let details: [KeyValueSummary]
}

public struct DylibSummary: Sendable {
    public let command: UInt32
    public let path: String
}

public struct SegmentSummary: Sendable {
    public let command: UInt32
    public let name: String
    public let vmAddress: UInt64
    public let vmSize: UInt64
    public let fileOffset: UInt64
    public let fileSize: UInt64
    public let maxProtection: Int32
    public let initialProtection: Int32
    public let flags: UInt32
    public let sections: [SectionSummary]
}

public struct SectionSummary: Sendable {
    public let name: String
    public let segmentName: String
    public let address: UInt64
    public let size: UInt64
    public let fileOffset: UInt32
    public let alignment: UInt32
    public let relocationOffset: UInt32
    public let relocationCount: UInt32
    public let flags: UInt32
}

public struct SymbolSummary: Sendable {
    public let name: String
    public let type: UInt8
    public let sectionNumber: UInt8
    public let description: UInt16
    public let value: UInt64
}

public struct LinkEditDataSummary: Sendable {
    public let command: UInt32
    public let dataOffset: UInt32
    public let dataSize: UInt32
}

public struct EncryptionSummary: Sendable {
    public let command: UInt32
    public let cryptOffset: UInt32
    public let cryptSize: UInt32
    public let cryptID: UInt32
}

public struct KeyValueSummary: Sendable {
    public let key: String
    public let value: String
}

public struct DocumentAnalysisService: Sendable {
    public init() {}

    public func analyze(url: URL) throws -> DocumentAnalysis {
        let container = try MachOContainer.parse(at: url)
        let slices = container.slices.map { slice in
            SliceSummary(
                fileOffset: slice.offset,
                is64Bit: slice.is64Bit,
                header: HeaderSummary(
                    cpuType: slice.header.cpuType,
                    cpuSubtype: slice.header.cpuSubtype,
                    fileType: slice.header.fileType,
                    numberOfCommands: slice.header.numberOfCommands,
                    sizeofCommands: slice.header.sizeofCommands,
                    flags: slice.header.flags,
                    reserved: slice.header.reserved
                ),
                loadCommandCount: slice.loadCommands.count,
                loadCommands: slice.loadCommands.map(makeLoadCommandSummary),
                platform: slice.buildVersion?.platform ?? slice.versionMin?.platform,
                minimumOS: slice.buildVersion?.minimumOS ?? slice.versionMin?.minimumOS,
                sdkVersion: slice.buildVersion?.sdk ?? slice.versionMin?.sdk,
                installName: slice.installName,
                dylibReferences: slice.dylibReferences.map { DylibSummary(command: $0.command, path: $0.path) },
                rpaths: slice.rpaths,
                segments: slice.segments.map(makeSegmentSummary),
                symbols: slice.symbols.map {
                    SymbolSummary(
                        name: $0.name,
                        type: $0.type,
                        sectionNumber: $0.sectionNumber,
                        description: $0.description,
                        value: $0.value
                    )
                },
                uuid: slice.uuid,
                hasCodeSignature: slice.codeSignature != nil,
                codeSignature: slice.codeSignature.map {
                    LinkEditDataSummary(
                        command: $0.command,
                        dataOffset: $0.dataOffset,
                        dataSize: $0.dataSize
                    )
                },
                encryptionInfo: slice.encryptionInfo.map {
                    EncryptionSummary(
                        command: $0.command,
                        cryptOffset: $0.cryptOffset,
                        cryptSize: $0.cryptSize,
                        cryptID: $0.cryptID
                    )
                }
            )
        }

        return DocumentAnalysis(
            fileURL: url,
            containerKind: container.kind,
            slices: slices
        )
    }

    private func makeLoadCommandSummary(_ command: MachOLoadCommandInfo) -> LoadCommandSummary {
        LoadCommandSummary(
            command: command.command,
            size: command.size,
            offset: command.offset,
            details: loadCommandDetails(for: command)
        )
    }

    private func loadCommandDetails(for command: MachOLoadCommandInfo) -> [KeyValueSummary] {
        switch command.payload {
        case let .dylib(info):
            return [
                KeyValueSummary(key: "path", value: info.path),
                KeyValueSummary(key: "currentVersion", value: info.currentVersion.description),
                KeyValueSummary(key: "compatibilityVersion", value: info.compatibilityVersion.description),
            ]
        case let .rpath(info):
            return [KeyValueSummary(key: "path", value: info.path)]
        case let .buildVersion(info):
            return [
                KeyValueSummary(key: "platform", value: String(describing: info.platform)),
                KeyValueSummary(key: "minimumOS", value: info.minimumOS.description),
                KeyValueSummary(key: "sdk", value: info.sdk.description),
            ]
        case let .versionMin(info):
            return [
                KeyValueSummary(key: "platform", value: String(describing: info.platform)),
                KeyValueSummary(key: "minimumOS", value: info.minimumOS.description),
                KeyValueSummary(key: "sdk", value: info.sdk.description),
            ]
        case let .segment(info):
            return [
                KeyValueSummary(key: "name", value: info.name),
                KeyValueSummary(key: "vmAddress", value: hex(info.vmAddress)),
                KeyValueSummary(key: "vmSize", value: hex(info.vmSize)),
                KeyValueSummary(key: "fileOffset", value: hex(info.fileOffset)),
                KeyValueSummary(key: "fileSize", value: hex(info.fileSize)),
            ]
        case let .symbolTable(info):
            return [
                KeyValueSummary(key: "symbolOffset", value: hex(info.symbolOffset)),
                KeyValueSummary(key: "symbolCount", value: "\(info.symbolCount)"),
                KeyValueSummary(key: "stringTableOffset", value: hex(info.stringTableOffset)),
                KeyValueSummary(key: "stringTableSize", value: hex(info.stringTableSize)),
            ]
        case let .uuid(uuid):
            return [KeyValueSummary(key: "uuid", value: uuid.uuidString)]
        case let .codeSignature(info):
            return [
                KeyValueSummary(key: "dataOffset", value: hex(info.dataOffset)),
                KeyValueSummary(key: "dataSize", value: hex(info.dataSize)),
            ]
        case let .encryptionInfo(info):
            return [
                KeyValueSummary(key: "cryptOffset", value: hex(info.cryptOffset)),
                KeyValueSummary(key: "cryptSize", value: hex(info.cryptSize)),
                KeyValueSummary(key: "cryptID", value: "\(info.cryptID)"),
            ]
        case nil:
            return []
        }
    }

    private func makeSegmentSummary(_ segment: SegmentInfo) -> SegmentSummary {
        SegmentSummary(
            command: segment.command,
            name: segment.name,
            vmAddress: segment.vmAddress,
            vmSize: segment.vmSize,
            fileOffset: segment.fileOffset,
            fileSize: segment.fileSize,
            maxProtection: segment.maxProtection.rawValue,
            initialProtection: segment.initialProtection.rawValue,
            flags: segment.flags,
            sections: segment.sections.map {
                SectionSummary(
                    name: $0.name,
                    segmentName: $0.segmentName,
                    address: $0.address,
                    size: $0.size,
                    fileOffset: $0.fileOffset,
                    alignment: $0.alignment,
                    relocationOffset: $0.relocationOffset,
                    relocationCount: $0.relocationCount,
                    flags: $0.flags
                )
            }
        )
    }

    private func hex(_ value: UInt32) -> String {
        "0x" + String(value, radix: 16, uppercase: true)
    }

    private func hex(_ value: UInt64) -> String {
        "0x" + String(value, radix: 16, uppercase: true)
    }
}

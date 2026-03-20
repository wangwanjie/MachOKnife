import Foundation

public struct MachOContainer: Sendable {
    public enum Kind: Sendable {
        case thin
        case fat
    }

    public let kind: Kind
    public let slices: [MachOSlice]

    public static func parse(at url: URL) throws -> MachOContainer {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let parser = MachOFileParser(data: data)
        return try parser.parseContainer()
    }
}

public struct MachOSlice: Sendable {
    public let offset: Int
    public let header: MachOHeaderInfo
    public let loadCommands: [MachOLoadCommandInfo]
    public let installNameInfo: DylibCommandInfo?
    public let dylibReferences: [DylibCommandInfo]
    public let rpathCommands: [RPathCommandInfo]
    public let buildVersion: BuildVersionInfo?
    public let versionMin: VersionMinInfo?
    public let segments: [SegmentInfo]
    public let uuid: UUID?
    public let codeSignature: LinkEditDataInfo?
    public let encryptionInfo: EncryptionInfo?

    public var is64Bit: Bool {
        header.is64Bit
    }

    public var installName: String? {
        installNameInfo?.path
    }

    public var rpaths: [String] {
        rpathCommands.map(\.path)
    }
}

public struct MachOHeaderInfo: Sendable {
    public let is64Bit: Bool
    public let cpuType: Int32
    public let cpuSubtype: Int32
    public let fileType: UInt32
    public let numberOfCommands: UInt32
    public let sizeofCommands: UInt32
    public let flags: UInt32
    public let reserved: UInt32?
}

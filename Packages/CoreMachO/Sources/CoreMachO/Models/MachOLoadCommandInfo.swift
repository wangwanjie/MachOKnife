import Foundation

public struct MachOLoadCommandInfo: Sendable {
    public let command: UInt32
    public let size: UInt32
    public let offset: Int
    public let payload: Payload?

    public enum Payload: Sendable {
        case dylib(DylibCommandInfo)
        case rpath(RPathCommandInfo)
        case buildVersion(BuildVersionInfo)
        case versionMin(VersionMinInfo)
        case segment(SegmentInfo)
        case symbolTable(SymbolTableInfo)
        case uuid(UUID)
        case codeSignature(LinkEditDataInfo)
        case encryptionInfo(EncryptionInfo)
    }
}

public typealias MachOLoadCommand = MachOLoadCommandInfo

public struct DylibCommandInfo: Sendable {
    public let command: UInt32
    public let path: String
    public let commandOffset: Int
    public let nameOffset: UInt32
    public let timestamp: UInt32
    public let currentVersion: MachOVersion
    public let compatibilityVersion: MachOVersion
}

public typealias DylibReference = DylibCommandInfo

public struct RPathCommandInfo: Sendable {
    public let command: UInt32
    public let path: String
    public let commandOffset: Int
    public let pathOffset: UInt32
}

public struct LinkEditDataInfo: Sendable {
    public let command: UInt32
    public let commandOffset: Int
    public let dataOffset: UInt32
    public let dataSize: UInt32
}

public struct EncryptionInfo: Sendable {
    public let command: UInt32
    public let commandOffset: Int
    public let cryptOffset: UInt32
    public let cryptSize: UInt32
    public let cryptID: UInt32
}

public struct SymbolTableInfo: Sendable {
    public let command: UInt32
    public let commandOffset: Int
    public let symbolOffset: UInt32
    public let symbolCount: UInt32
    public let stringTableOffset: UInt32
    public let stringTableSize: UInt32
}

public struct SymbolInfo: Sendable {
    public let name: String
    public let stringTableIndex: UInt32
    public let type: UInt8
    public let sectionNumber: UInt8
    public let description: UInt16
    public let value: UInt64
}

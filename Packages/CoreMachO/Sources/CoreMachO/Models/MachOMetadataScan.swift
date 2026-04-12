import Foundation

public struct MachOMetadataScan: Sendable {
    public let fileURL: URL
    public let fileSize: Int
    public let kind: MachOContainer.Kind
    public let slices: [MachOMetadataSlice]

    public init(
        fileURL: URL,
        fileSize: Int,
        kind: MachOContainer.Kind,
        slices: [MachOMetadataSlice]
    ) {
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.kind = kind
        self.slices = slices
    }
}

public struct MachOMetadataSlice: Sendable {
    public let offset: Int
    public let header: MachOHeaderInfo
    public let loadCommands: [MachOLoadCommandInfo]
    public let installNameInfo: DylibCommandInfo?
    public let dylibReferences: [DylibCommandInfo]
    public let rpathCommands: [RPathCommandInfo]
    public let buildVersion: BuildVersionInfo?
    public let versionMin: VersionMinInfo?
    public let segments: [SegmentInfo]
    public let symbolTable: SymbolTableInfo?
    public let uuid: UUID?
    public let codeSignature: LinkEditDataInfo?
    public let encryptionInfo: EncryptionInfo?
    public let heavyCollectionEstimate: MachOHeavyCollectionEstimate
    public let isByteSwapped: Bool

    public init(
        offset: Int,
        header: MachOHeaderInfo,
        loadCommands: [MachOLoadCommandInfo],
        installNameInfo: DylibCommandInfo?,
        dylibReferences: [DylibCommandInfo],
        rpathCommands: [RPathCommandInfo],
        buildVersion: BuildVersionInfo?,
        versionMin: VersionMinInfo?,
        segments: [SegmentInfo],
        symbolTable: SymbolTableInfo?,
        uuid: UUID?,
        codeSignature: LinkEditDataInfo?,
        encryptionInfo: EncryptionInfo?,
        heavyCollectionEstimate: MachOHeavyCollectionEstimate,
        isByteSwapped: Bool
    ) {
        self.offset = offset
        self.header = header
        self.loadCommands = loadCommands
        self.installNameInfo = installNameInfo
        self.dylibReferences = dylibReferences
        self.rpathCommands = rpathCommands
        self.buildVersion = buildVersion
        self.versionMin = versionMin
        self.segments = segments
        self.symbolTable = symbolTable
        self.uuid = uuid
        self.codeSignature = codeSignature
        self.encryptionInfo = encryptionInfo
        self.heavyCollectionEstimate = heavyCollectionEstimate
        self.isByteSwapped = isByteSwapped
    }

    public var is64Bit: Bool {
        header.is64Bit
    }

    public var installName: String? {
        installNameInfo?.path
    }
}

public struct MachOHeavyCollectionEstimate: Sendable {
    public let symbolCount: Int
    public let stringTableSize: Int
    public let estimatedNodeCount: Int

    public init(symbolCount: Int, stringTableSize: Int, estimatedNodeCount: Int) {
        self.symbolCount = symbolCount
        self.stringTableSize = stringTableSize
        self.estimatedNodeCount = estimatedNodeCount
    }
}

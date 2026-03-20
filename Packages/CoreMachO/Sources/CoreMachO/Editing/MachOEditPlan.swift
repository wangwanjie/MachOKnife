import Foundation

public struct MachOEditPlan: Sendable {
    public let installName: String?
    public let dylibEdits: [DylibEdit]
    public let rpathEdits: [RPathEdit]
    public let platformEdit: PlatformEdit?
    public let segmentProtectionEdits: [SegmentProtectionEdit]
    public let stripCodeSignature: Bool

    public init(
        installName: String? = nil,
        dylibEdits: [DylibEdit] = [],
        rpathEdits: [RPathEdit] = [],
        platformEdit: PlatformEdit? = nil,
        segmentProtectionEdits: [SegmentProtectionEdit] = [],
        stripCodeSignature: Bool = false
    ) {
        self.installName = installName
        self.dylibEdits = dylibEdits
        self.rpathEdits = rpathEdits
        self.platformEdit = platformEdit
        self.segmentProtectionEdits = segmentProtectionEdits
        self.stripCodeSignature = stripCodeSignature
    }
}

public enum DylibEdit: Sendable {
    case replace(oldPath: String, newPath: String, command: UInt32? = nil)
    case add(path: String, command: UInt32)
    case remove(path: String, command: UInt32? = nil)
}

public enum RPathEdit: Sendable {
    case add(String)
    case replace(oldPath: String, newPath: String)
    case remove(String)
}

public struct PlatformEdit: Sendable {
    public let platform: MachOPlatform
    public let minimumOS: MachOVersion
    public let sdk: MachOVersion

    public init(platform: MachOPlatform, minimumOS: MachOVersion, sdk: MachOVersion) {
        self.platform = platform
        self.minimumOS = minimumOS
        self.sdk = sdk
    }
}

public struct SegmentProtectionEdit: Sendable {
    public let segmentName: String
    public let maxProtection: SegmentProtection?
    public let initialProtection: SegmentProtection?

    public init(segmentName: String, maxProtection: SegmentProtection? = nil, initialProtection: SegmentProtection? = nil) {
        self.segmentName = segmentName
        self.maxProtection = maxProtection
        self.initialProtection = initialProtection
    }
}

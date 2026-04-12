import CoreMachO
import Foundation

struct EditableDylibReference: Equatable, Sendable {
    let index: Int
    let command: UInt32
    var path: String
}

struct EditablePlatformMetadata: Equatable, Sendable {
    let originalPlatform: MachOPlatform?
    let originalMinimumOS: MachOVersion?
    let originalSDK: MachOVersion?
    var platform: MachOPlatform
    var minimumOS: MachOVersion
    var sdk: MachOVersion

    var hasChanges: Bool {
        originalPlatform != platform ||
        originalMinimumOS != minimumOS ||
        originalSDK != sdk
    }
}

struct EditableSliceViewModel: Equatable, Sendable {
    let sliceIndex: Int
    var installName: String
    var dylibReferences: [EditableDylibReference]
    var rpaths: [String]
    var platformMetadata: EditablePlatformMetadata?

    init(
        sliceIndex: Int,
        installName: String,
        dylibReferences: [EditableDylibReference],
        rpaths: [String],
        platformMetadata: EditablePlatformMetadata?
    ) {
        self.sliceIndex = sliceIndex
        self.installName = installName
        self.dylibReferences = dylibReferences
        self.rpaths = rpaths
        self.platformMetadata = platformMetadata
    }
}

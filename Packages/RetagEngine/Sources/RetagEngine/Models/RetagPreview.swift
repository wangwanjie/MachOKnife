import Foundation
import CoreMachO

public struct RetagPreview: Sendable {
    public let diff: MachODiff

    public init(diff: MachODiff) {
        self.diff = diff
    }
}

public struct RetagResult: Sendable {
    public let outputURL: URL
    public let diff: MachODiff

    public init(outputURL: URL, diff: MachODiff) {
        self.outputURL = outputURL
        self.diff = diff
    }
}

import CoreMachO
import Foundation

public struct DocumentEditPreview: Sendable {
    public let inputURL: URL
    public let diff: MachODiff

    public init(inputURL: URL, diff: MachODiff) {
        self.inputURL = inputURL
        self.diff = diff
    }
}

public struct DocumentSaveResult: Sendable {
    public let outputURL: URL
    public let backupURL: URL?
    public let diff: MachODiff

    public init(outputURL: URL, backupURL: URL?, diff: MachODiff) {
        self.outputURL = outputURL
        self.backupURL = backupURL
        self.diff = diff
    }
}

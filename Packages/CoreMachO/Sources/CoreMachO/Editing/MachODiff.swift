import Foundation

public struct MachODiff: Sendable {
    public let entries: [DiffEntry]

    public init(entries: [DiffEntry] = []) {
        self.entries = entries
    }
}

public struct DiffEntry: Sendable {
    public enum Kind: Sendable {
        case installName
        case dylib
        case rpath
        case platform
        case segmentProtection
        case codeSignature
    }

    public let sliceOffset: Int
    public let kind: Kind
    public let originalValue: String?
    public let updatedValue: String?

    public init(sliceOffset: Int, kind: Kind, originalValue: String?, updatedValue: String?) {
        self.sliceOffset = sliceOffset
        self.kind = kind
        self.originalValue = originalValue
        self.updatedValue = updatedValue
    }
}

public struct MachOWriteResult: Sendable {
    public let outputURL: URL
    public let diff: MachODiff
    public let removedCodeSignature: Bool

    public init(outputURL: URL, diff: MachODiff, removedCodeSignature: Bool) {
        self.outputURL = outputURL
        self.diff = diff
        self.removedCodeSignature = removedCodeSignature
    }
}

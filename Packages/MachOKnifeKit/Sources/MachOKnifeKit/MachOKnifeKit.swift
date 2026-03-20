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
    public let loadCommandCount: Int
    public let installName: String?
    public let dylibReferences: [DylibSummary]
    public let rpaths: [String]
}

public struct DylibSummary: Sendable {
    public let command: UInt32
    public let path: String
}

public struct DocumentAnalysisService: Sendable {
    public init() {}

    public func analyze(url: URL) throws -> DocumentAnalysis {
        let container = try MachOContainer.parse(at: url)
        let slices = container.slices.map { slice in
            SliceSummary(
                fileOffset: slice.offset,
                is64Bit: slice.is64Bit,
                loadCommandCount: slice.loadCommands.count,
                installName: slice.installName,
                dylibReferences: slice.dylibReferences.map { DylibSummary(command: $0.command, path: $0.path) },
                rpaths: slice.rpaths
            )
        }

        return DocumentAnalysis(
            fileURL: url,
            containerKind: container.kind,
            slices: slices
        )
    }
}

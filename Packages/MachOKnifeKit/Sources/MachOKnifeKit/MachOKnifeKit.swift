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
}

public struct DocumentAnalysisService: Sendable {
    public init() {}

    public func analyze(url: URL) throws -> DocumentAnalysis {
        let container = try MachOContainer.parse(at: url)
        let slices = container.slices.map { slice in
            SliceSummary(
                fileOffset: slice.offset,
                is64Bit: slice.is64Bit,
                loadCommandCount: slice.loadCommands.count
            )
        }

        return DocumentAnalysis(
            fileURL: url,
            containerKind: container.kind,
            slices: slices
        )
    }
}

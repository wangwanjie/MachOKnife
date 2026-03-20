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
    public let platform: MachOPlatform?
    public let minimumOS: MachOVersion?
    public let sdkVersion: MachOVersion?
    public let installName: String?
    public let dylibReferences: [DylibSummary]
    public let rpaths: [String]
    public let hasCodeSignature: Bool
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
                platform: slice.buildVersion?.platform ?? slice.versionMin?.platform,
                minimumOS: slice.buildVersion?.minimumOS ?? slice.versionMin?.minimumOS,
                sdkVersion: slice.buildVersion?.sdk ?? slice.versionMin?.sdk,
                installName: slice.installName,
                dylibReferences: slice.dylibReferences.map { DylibSummary(command: $0.command, path: $0.path) },
                rpaths: slice.rpaths,
                hasCodeSignature: slice.codeSignature != nil
            )
        }

        return DocumentAnalysis(
            fileURL: url,
            containerKind: container.kind,
            slices: slices
        )
    }
}

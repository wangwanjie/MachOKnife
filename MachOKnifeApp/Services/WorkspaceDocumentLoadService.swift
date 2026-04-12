import CoreMachO
import Foundation
import MachOKnifeKit

struct WorkspaceDocumentLoadService: Sendable {
    typealias MetadataLoader = @Sendable (URL, AnalysisBudget) throws -> MetadataStage

    struct MetadataStage: Sendable {
        let scan: MachOMetadataScan
        let decision: AnalysisBudgetDecision
        let analysis: DocumentAnalysis
    }

    private let metadataLoader: MetadataLoader

    nonisolated init(metadataLoader: @escaping MetadataLoader = Self.makeMetadataStage) {
        self.metadataLoader = metadataLoader
    }

    nonisolated
    func loadMetadataStage(
        at url: URL,
        analysisBudget: AnalysisBudget
    ) throws -> MetadataStage {
        try metadataLoader(url, analysisBudget)
    }

    nonisolated
    private static func makeMetadataStage(
        at url: URL,
        analysisBudget: AnalysisBudget
    ) throws -> MetadataStage {
        let scan = try MachOContainer.scan(at: url)
        let decision = analysisBudget.classify(scan: scan)
        let analysis = try DocumentAnalysisService().analyze(scan: scan)

        return MetadataStage(
            scan: scan,
            decision: decision,
            analysis: analysis
        )
    }
}

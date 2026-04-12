import CoreMachO
import Foundation

public enum AnalysisMode: Sendable {
    case normal
    case budgetedLargeFile
}

public enum AnalysisBudgetLimit: Hashable, Sendable {
    case fileSize
    case symbolCount
    case stringTableSize
    case estimatedNodeCount
}

public struct AnalysisBudgetDecision: Sendable {
    public let mode: AnalysisMode
    public let exceededLimits: Set<AnalysisBudgetLimit>

    public init(mode: AnalysisMode, exceededLimits: Set<AnalysisBudgetLimit>) {
        self.mode = mode
        self.exceededLimits = exceededLimits
    }
}

public struct AnalysisBudget: Sendable {
    public let maximumFileSize: Int
    public let maximumSymbolCount: Int
    public let maximumStringTableSize: Int
    public let maximumEstimatedNodeCount: Int

    public init(
        maximumFileSize: Int,
        maximumSymbolCount: Int,
        maximumStringTableSize: Int,
        maximumEstimatedNodeCount: Int
    ) {
        self.maximumFileSize = maximumFileSize
        self.maximumSymbolCount = maximumSymbolCount
        self.maximumStringTableSize = maximumStringTableSize
        self.maximumEstimatedNodeCount = maximumEstimatedNodeCount
    }

    public static let workspaceDefault = AnalysisBudget(
        maximumFileSize: 64 * 1_024 * 1_024,
        maximumSymbolCount: 20_000,
        maximumStringTableSize: 2 * 1_024 * 1_024,
        maximumEstimatedNodeCount: 40_000
    )

    public func classify(scan: MachOMetadataScan) -> AnalysisBudgetDecision {
        let symbolCount = scan.slices.reduce(0) { $0 + $1.heavyCollectionEstimate.symbolCount }
        let stringTableSize = scan.slices.reduce(0) { $0 + $1.heavyCollectionEstimate.stringTableSize }
        let estimatedNodeCount = scan.slices.reduce(0) { $0 + $1.heavyCollectionEstimate.estimatedNodeCount }

        var exceededLimits = Set<AnalysisBudgetLimit>()
        if scan.fileSize > maximumFileSize {
            exceededLimits.insert(.fileSize)
        }
        if symbolCount > maximumSymbolCount {
            exceededLimits.insert(.symbolCount)
        }
        if stringTableSize > maximumStringTableSize {
            exceededLimits.insert(.stringTableSize)
        }
        if estimatedNodeCount > maximumEstimatedNodeCount {
            exceededLimits.insert(.estimatedNodeCount)
        }

        return AnalysisBudgetDecision(
            mode: exceededLimits.isEmpty ? .normal : .budgetedLargeFile,
            exceededLimits: exceededLimits
        )
    }
}

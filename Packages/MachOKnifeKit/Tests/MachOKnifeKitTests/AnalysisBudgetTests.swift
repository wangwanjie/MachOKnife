import CoreMachO
import Foundation
import Testing
@testable import MachOKnifeKit

struct AnalysisBudgetTests {
    @Test("keeps small scans on the normal path")
    func keepsSmallScansOnTheNormalPath() {
        let budget = AnalysisBudget(
            maximumFileSize: 10_000,
            maximumSymbolCount: 1_000,
            maximumStringTableSize: 8_192,
            maximumEstimatedNodeCount: 2_000
        )

        let decision = budget.classify(scan: smallScan())

        #expect(decision.mode == .normal)
        #expect(decision.exceededLimits.isEmpty)
    }

    @Test("moves large scans to the budgeted path and reports why")
    func movesLargeScansToTheBudgetedPathAndReportsWhy() {
        let budget = AnalysisBudget(
            maximumFileSize: 2_048,
            maximumSymbolCount: 32,
            maximumStringTableSize: 512,
            maximumEstimatedNodeCount: 128
        )

        let decision = budget.classify(scan: largeScan())

        #expect(decision.mode == .budgetedLargeFile)
        #expect(decision.exceededLimits.contains(.fileSize))
        #expect(decision.exceededLimits.contains(.symbolCount))
        #expect(decision.exceededLimits.contains(.stringTableSize))
        #expect(decision.exceededLimits.contains(.estimatedNodeCount))
    }
}

private func smallScan() -> MachOMetadataScan {
    MachOMetadataScan(
        fileURL: URL(filePath: "/tmp/small"),
        fileSize: 1_024,
        kind: .thin,
        slices: [
            MachOMetadataSlice(
                offset: 0,
                header: MachOHeaderInfo(
                    is64Bit: true,
                    cpuType: 0,
                    cpuSubtype: 0,
                    fileType: 0,
                    numberOfCommands: 4,
                    sizeofCommands: 128,
                    flags: 0,
                    reserved: nil
                ),
                loadCommands: [],
                installNameInfo: nil,
                dylibReferences: [],
                rpathCommands: [],
                buildVersion: nil,
                versionMin: nil,
                segments: [],
                symbolTable: SymbolTableInfo(
                    command: 0,
                    commandOffset: 0,
                    symbolOffset: 256,
                    symbolCount: 8,
                    stringTableOffset: 512,
                    stringTableSize: 128
                ),
                uuid: nil,
                codeSignature: nil,
                encryptionInfo: nil,
                heavyCollectionEstimate: MachOHeavyCollectionEstimate(
                    symbolCount: 8,
                    stringTableSize: 128,
                    estimatedNodeCount: 24
                ),
                isByteSwapped: false
            ),
        ]
    )
}

private func largeScan() -> MachOMetadataScan {
    MachOMetadataScan(
        fileURL: URL(filePath: "/tmp/large"),
        fileSize: 8_192,
        kind: .thin,
        slices: [
            MachOMetadataSlice(
                offset: 0,
                header: MachOHeaderInfo(
                    is64Bit: true,
                    cpuType: 0,
                    cpuSubtype: 0,
                    fileType: 0,
                    numberOfCommands: 10,
                    sizeofCommands: 640,
                    flags: 0,
                    reserved: nil
                ),
                loadCommands: [],
                installNameInfo: nil,
                dylibReferences: [],
                rpathCommands: [],
                buildVersion: nil,
                versionMin: nil,
                segments: [],
                symbolTable: SymbolTableInfo(
                    command: 0,
                    commandOffset: 0,
                    symbolOffset: 1_024,
                    symbolCount: 256,
                    stringTableOffset: 4_096,
                    stringTableSize: 2_048
                ),
                uuid: nil,
                codeSignature: nil,
                encryptionInfo: nil,
                heavyCollectionEstimate: MachOHeavyCollectionEstimate(
                    symbolCount: 256,
                    stringTableSize: 2_048,
                    estimatedNodeCount: 1_024
                ),
                isByteSwapped: false
            ),
        ]
    )
}

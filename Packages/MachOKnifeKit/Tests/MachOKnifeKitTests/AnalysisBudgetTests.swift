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

extension AnalysisBudgetTests {
    @Test("values exactly at the limits stay on the normal path")
    func valuesAtTheLimitsStayNormal() {
        // smallScan 的文件大小 1_024、符号 8、字符串表 128、估算节点 24，全部恰好等于上限。
        let budget = AnalysisBudget(
            maximumFileSize: 1_024,
            maximumSymbolCount: 8,
            maximumStringTableSize: 128,
            maximumEstimatedNodeCount: 24
        )

        let decision = budget.classify(scan: smallScan())

        #expect(decision.mode == .normal)
        #expect(decision.exceededLimits.isEmpty)
    }

    @Test("a single exceeded limit is reported on its own")
    func singleExceededLimitIsReportedAlone() {
        let budget = AnalysisBudget(
            maximumFileSize: 1_024,
            maximumSymbolCount: 7,
            maximumStringTableSize: 128,
            maximumEstimatedNodeCount: 24
        )

        let decision = budget.classify(scan: smallScan())

        #expect(decision.mode == .budgetedLargeFile)
        #expect(decision.exceededLimits == [.symbolCount])
    }

    @Test("estimates from every slice of a universal binary are summed")
    func estimatesAreSummedAcrossSlices() {
        let single = smallScan()
        let slice = single.slices[0]
        let universal = MachOMetadataScan(fileURL: single.fileURL, fileSize: single.fileSize, kind: .fat, slices: [slice, slice])
        // 单个切片 8 个符号未超限，两个切片合计 16 个超过 15。
        let budget = AnalysisBudget(
            maximumFileSize: 1_024,
            maximumSymbolCount: 15,
            maximumStringTableSize: 256,
            maximumEstimatedNodeCount: 48
        )

        #expect(budget.classify(scan: single).mode == .normal)
        #expect(budget.classify(scan: universal).exceededLimits == [.symbolCount])
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

import Foundation
import MachOKnifeKit

struct ValidateCommand {
    static let name = "validate"
    static let usage = "machoe-cli validate <path>"

    /// Exit status used when validation found structural problems.
    static let failureExitCode: Int32 = 1

    static func run(arguments: [String]) throws -> String {
        let parsed = try CLICommandSupport.parse(arguments, valueOptions: [], usage: usage)
        let inputURL = try CLICommandSupport.requiredPath(parsed, usage: usage)
        let analysis = try DocumentAnalysisService().analyze(url: inputURL)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? NSNumber)?.uint64Value
        let report = CLIValidator.validate(analysis, fileSize: fileSize)
        let output = CLIReportRenderer.renderValidation(analysis, report: report)
        guard report.errors.isEmpty else {
            throw CLICommandFailure(output: output, exitCode: failureExitCode)
        }
        return output
    }
}

struct CLIValidationReport {
    var errors: [String] = []
    var warnings: [String] = []
}

/// Structural checks over the parsed Mach-O metadata.
enum CLIValidator {
    private static let mhDylib: UInt32 = 0x6

    static func validate(_ analysis: DocumentAnalysis, fileSize: UInt64?) -> CLIValidationReport {
        var report = CLIValidationReport()

        if analysis.slices.isEmpty {
            report.errors.append("No Mach-O slices were found.")
        }

        for (index, slice) in analysis.slices.enumerated() {
            let prefix = "Slice \(index):"
            let header = slice.header

            if Int(header.numberOfCommands) != slice.loadCommandCount {
                report.errors.append("\(prefix) header declares \(header.numberOfCommands) load commands but \(slice.loadCommandCount) were parsed.")
            }

            let alignment: UInt32 = slice.is64Bit ? 8 : 4
            var totalCommandSize: UInt64 = 0
            for command in slice.loadCommands {
                totalCommandSize += UInt64(command.size)
                if command.size == 0 {
                    report.errors.append("\(prefix) load command 0x\(String(command.command, radix: 16)) at offset \(command.offset) has size 0.")
                } else if command.size % alignment != 0 {
                    report.warnings.append("\(prefix) load command 0x\(String(command.command, radix: 16)) at offset \(command.offset) size \(command.size) is not \(alignment)-byte aligned.")
                }
            }
            if slice.loadCommands.isEmpty == false, totalCommandSize != UInt64(header.sizeofCommands) {
                report.errors.append("\(prefix) load commands occupy \(totalCommandSize) bytes but the header declares \(header.sizeofCommands).")
            }

            if let fileSize {
                let sliceStart = UInt64(max(slice.fileOffset, 0))
                let available = fileSize > sliceStart ? fileSize - sliceStart : 0
                let headerSize: UInt64 = slice.is64Bit ? 32 : 28
                if headerSize + UInt64(header.sizeofCommands) > available {
                    report.errors.append("\(prefix) load commands extend past the end of the file.")
                }
                for segment in slice.segments where segment.fileSize > 0 {
                    let (end, overflow) = segment.fileOffset.addingReportingOverflow(segment.fileSize)
                    if overflow || end > available {
                        report.errors.append("\(prefix) segment \(segment.name) extends past the end of the file.")
                    }
                }
                if let signature = slice.codeSignature,
                   UInt64(signature.dataOffset) + UInt64(signature.dataSize) > available {
                    report.errors.append("\(prefix) code signature extends past the end of the file.")
                }
            }

            if header.fileType == mhDylib, (slice.installName ?? "").isEmpty {
                report.errors.append("\(prefix) dylib has no install name (LC_ID_DYLIB).")
            }
            if slice.platform == nil {
                report.warnings.append("\(prefix) no LC_BUILD_VERSION or LC_VERSION_MIN_* platform information.")
            }
        }

        return report
    }
}

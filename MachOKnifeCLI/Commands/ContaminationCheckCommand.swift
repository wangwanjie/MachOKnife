import Foundation
import MachOKnifeKit

struct ContaminationCheckCommand {
    static let name = "check-contamination"
    static let usage = "machoe-cli check-contamination <path> --mode platform|architecture --target <value>"

    /// Exit status used when the check completed but found mismatching slices.
    static let mismatchExitCode: Int32 = 1

    static func run(arguments: [String]) throws -> String {
        let parsed = try CLICommandSupport.parse(arguments, valueOptions: ["--mode", "--target"], usage: usage)
        let inputURL = try CLICommandSupport.requiredPath(parsed, usage: usage)
        let modeValue = try parsed.requiredValue("--mode", usage: usage)
        let targetValue = try parsed.requiredValue("--target", usage: usage)

        let mode: BinaryContaminationCheckMode
        switch modeValue.lowercased() {
        case "platform":
            mode = .platform
        case "architecture", "arch":
            mode = .architecture
        default:
            throw CLIError.invalidUsage(usage, detail: "unsupported mode '\(modeValue)'")
        }

        let report = try BinaryContaminationCheckService().runCheck(
            at: inputURL,
            target: targetValue,
            mode: mode
        )
        let output = report.renderedText + "\n"
        guard report.mismatchCount == 0 else {
            throw CLICommandFailure(output: output, exitCode: mismatchExitCode)
        }
        return output
    }
}

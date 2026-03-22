import Foundation
import MachOKnifeKit

struct ContaminationCheckCommand {
    static let name = "check-contamination"
    static let usage = "machoe-cli check-contamination <path> --mode platform|architecture --target <value>"

    static func run(arguments: [String]) throws -> String {
        let inputURL = try CLICommandSupport.requiredPath(arguments, usage: usage)
        let modeValue = try CLICommandSupport.requiredOption("--mode", in: arguments, usage: usage)
        let targetValue = try CLICommandSupport.requiredOption("--target", in: arguments, usage: usage)

        let mode: BinaryContaminationCheckMode
        switch modeValue.lowercased() {
        case "platform":
            mode = .platform
        case "architecture", "arch":
            mode = .architecture
        default:
            throw CLIError.invalidUsage(usage)
        }

        let report = try BinaryContaminationCheckService().runCheck(
            at: inputURL,
            target: targetValue,
            mode: mode
        )
        return report.renderedText + "\n"
    }
}

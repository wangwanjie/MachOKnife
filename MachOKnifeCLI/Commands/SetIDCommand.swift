import CoreMachO
import Foundation
import MachOKnifeKit

struct SetIDCommand {
    static let name = "set-id"
    static let usage = "machoe-cli set-id <path> --install-name <path> --output <path>"

    static func run(arguments: [String]) throws -> String {
        let inputURL = try CLICommandSupport.requiredPath(arguments, usage: usage)
        let installName = try CLICommandSupport.requiredOption("--install-name", in: arguments, usage: usage)
        let outputURL = URL(filePath: try CLICommandSupport.requiredOption("--output", in: arguments, usage: usage))

        let result = try DocumentEditingService().save(
            inputURL: inputURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(installName: installName),
            createBackup: false
        )

        return CLIReportRenderer.renderWrite(outputURL: result.outputURL, diff: result.diff)
    }
}

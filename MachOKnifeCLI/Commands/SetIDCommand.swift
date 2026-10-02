import CoreMachO
import Foundation
import MachOKnifeKit

struct SetIDCommand {
    static let name = "set-id"
    static let usage = "machoe-cli set-id <path> --install-name <path> --output <path>"

    static func run(arguments: [String]) throws -> String {
        let parsed = try CLICommandSupport.parse(arguments, valueOptions: ["--install-name", "--output"], usage: usage)
        let inputURL = try CLICommandSupport.requiredPath(parsed, usage: usage)
        let installName = try parsed.requiredValue("--install-name", usage: usage)
        let outputURL = URL(filePath: try parsed.requiredValue("--output", usage: usage))

        let result = try DocumentEditingService().save(
            inputURL: inputURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(installName: installName),
            createBackup: false
        )

        return CLIReportRenderer.renderWrite(outputURL: result.outputURL, diff: result.diff)
    }
}

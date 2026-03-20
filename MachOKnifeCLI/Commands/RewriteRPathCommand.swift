import CoreMachO
import Foundation
import MachOKnifeKit

struct RewriteRPathCommand {
    static let name = "rewrite-rpath"
    static let usage = "machoe-cli rewrite-rpath <path> --from <path> --to <path> --output <path>"

    static func run(arguments: [String]) throws -> String {
        let inputURL = try CLICommandSupport.requiredPath(arguments, usage: usage)
        let fromPath = try CLICommandSupport.requiredOption("--from", in: arguments, usage: usage)
        let toPath = try CLICommandSupport.requiredOption("--to", in: arguments, usage: usage)
        let outputURL = URL(filePath: try CLICommandSupport.requiredOption("--output", in: arguments, usage: usage))

        let result = try DocumentEditingService().save(
            inputURL: inputURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(rpathEdits: [.replace(oldPath: fromPath, newPath: toPath)]),
            createBackup: false
        )

        return CLIReportRenderer.renderWrite(outputURL: result.outputURL, diff: result.diff)
    }
}

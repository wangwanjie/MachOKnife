import CoreMachO
import Foundation
import MachOKnifeKit

struct RewriteRPathCommand {
    static let name = "rewrite-rpath"
    static let usage = "machoe-cli rewrite-rpath <path> --from <path> --to <path> --output <path>"

    static func run(arguments: [String]) throws -> String {
        let parsed = try CLICommandSupport.parse(arguments, valueOptions: ["--from", "--to", "--output"], usage: usage)
        let inputURL = try CLICommandSupport.requiredPath(parsed, usage: usage)
        let fromPath = try parsed.requiredValue("--from", usage: usage)
        let toPath = try parsed.requiredValue("--to", usage: usage)
        let outputURL = URL(filePath: try parsed.requiredValue("--output", usage: usage))

        let result = try DocumentEditingService().save(
            inputURL: inputURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(rpathEdits: [.replace(oldPath: fromPath, newPath: toPath)]),
            createBackup: false
        )

        return CLIReportRenderer.renderWrite(outputURL: result.outputURL, diff: result.diff)
    }
}

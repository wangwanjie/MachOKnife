import CoreMachO
import Foundation
import MachOKnifeKit

struct StripSignatureCommand {
    static let name = "strip-signature"
    static let usage = "machoe-cli strip-signature <path> --output <path>"

    static func run(arguments: [String]) throws -> String {
        let parsed = try CLICommandSupport.parse(arguments, valueOptions: ["--output"], usage: usage)
        let inputURL = try CLICommandSupport.requiredPath(parsed, usage: usage)
        let outputURL = URL(filePath: try parsed.requiredValue("--output", usage: usage))

        let result = try DocumentEditingService().save(
            inputURL: inputURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(stripCodeSignature: true),
            createBackup: false
        )

        return CLIReportRenderer.renderWrite(outputURL: result.outputURL, diff: result.diff)
    }
}

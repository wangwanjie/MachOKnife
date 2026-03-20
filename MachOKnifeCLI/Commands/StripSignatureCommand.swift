import CoreMachO
import Foundation
import MachOKnifeKit

struct StripSignatureCommand {
    static let name = "strip-signature"
    static let usage = "machoe-cli strip-signature <path> --output <path>"

    static func run(arguments: [String]) throws -> String {
        let inputURL = try CLICommandSupport.requiredPath(arguments, usage: usage)
        let outputURL = URL(filePath: try CLICommandSupport.requiredOption("--output", in: arguments, usage: usage))

        let result = try DocumentEditingService().save(
            inputURL: inputURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(stripCodeSignature: true),
            createBackup: false
        )

        return CLIReportRenderer.renderWrite(outputURL: result.outputURL, diff: result.diff)
    }
}

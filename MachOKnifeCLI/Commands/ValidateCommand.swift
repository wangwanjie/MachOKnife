import Foundation
import MachOKnifeKit

struct ValidateCommand {
    static let name = "validate"
    static let usage = "machoe-cli validate <path>"

    static func run(arguments: [String]) throws -> String {
        guard arguments.count == 1 else {
            throw CLIError.invalidUsage(usage)
        }

        let inputURL = try CLICommandSupport.requiredPath(arguments, usage: usage)
        let analysis = try DocumentAnalysisService().analyze(url: inputURL)
        return CLIReportRenderer.renderValidation(analysis)
    }
}

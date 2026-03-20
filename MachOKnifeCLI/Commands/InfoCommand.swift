import Foundation
import MachOKnifeKit

struct InfoCommand {
    static let name = "info"
    static let usage = "machoe-cli info <path>"

    static func run(arguments: [String]) throws -> String {
        guard arguments.count == 1 else {
            throw CLIError.invalidUsage(usage)
        }

        let url = try CLICommandSupport.requiredPath(arguments, usage: usage)
        let analysis = try DocumentAnalysisService().analyze(url: url)
        return CLIReportRenderer.renderInfo(analysis)
    }
}

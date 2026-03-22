import Foundation
import MachOKnifeKit

struct ListDylibsCommand {
    static let name = "list-dylibs"
    static let usage = "machoe-cli list-dylibs <path>"

    static func run(arguments: [String]) throws -> String {
        guard arguments.count == 1 else {
            throw CLIError.invalidUsage(usage)
        }

        let url = try CLICommandSupport.requiredPath(arguments, usage: usage)
        if let archiveAnalysis = try ArchiveAnalysisService().analyze(url: url) {
            return CLIReportRenderer.renderDylibs(archiveAnalysis)
        }
        let analysis = try DocumentAnalysisService().analyze(url: url)
        return CLIReportRenderer.renderDylibs(analysis)
    }
}

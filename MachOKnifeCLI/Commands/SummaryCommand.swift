import Foundation
import MachOKnifeKit

struct SummaryCommand {
    static let name = "summary"
    static let usage = "machoe-cli summary <path>"

    static func run(arguments: [String]) throws -> String {
        guard arguments.count == 1 else {
            throw CLIError.invalidUsage(usage)
        }

        let inputURL = try CLICommandSupport.requiredPath(arguments, usage: usage)
        let report = try BinarySummaryService().makeReport(for: inputURL)
        return report.renderedText + "\n"
    }
}

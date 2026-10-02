import Foundation
import MachOKnifeKit

struct SummaryCommand {
    static let name = "summary"
    static let usage = "machoe-cli summary <path>"

    static func run(arguments: [String]) throws -> String {
        let parsed = try CLICommandSupport.parse(arguments, valueOptions: [], usage: usage)
        let inputURL = try CLICommandSupport.requiredPath(parsed, usage: usage)
        let report = try BinarySummaryService().makeReport(for: inputURL)
        return report.renderedText + "\n"
    }
}

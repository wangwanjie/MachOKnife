import Foundation
import MachOKnifeKit

struct SummaryCommand {
    static let name = "summary"
    static let usage = "machoe-cli summary <path> [--json]"

    static func run(arguments: [String]) throws -> String {
        let parsed = try CLICommandSupport.parse(arguments, valueOptions: [], flagOptions: ["--json"], usage: usage)
        let inputURL = try CLICommandSupport.requiredPath(parsed, usage: usage)
        let report = try BinarySummaryService().makeReport(for: inputURL)
        // `--json` 直接复用 MachOKnifeKit 的 JSON 编码（title / summary / sections），保证 CLI 与库输出一致。
        if parsed.contains("--json") {
            return report.renderedJSON + "\n"
        }
        return report.renderedText + "\n"
    }
}

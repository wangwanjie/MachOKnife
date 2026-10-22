import Foundation
import MachOKnifeKit

struct ListDylibsCommand {
    static let name = "list-dylibs"
    static let usage = "machoe-cli list-dylibs <path> [--json]"

    static func run(arguments: [String]) throws -> String {
        let parsed = try CLICommandSupport.parse(arguments, valueOptions: [], flagOptions: ["--json"], usage: usage)
        let url = try CLICommandSupport.requiredPath(parsed, usage: usage)
        // 与 `info --json` 相同的约定：`--json` 输出稳定键名的 JSON，默认仍是人类可读文本。
        let wantsJSON = parsed.contains("--json")
        if let archiveAnalysis = try ArchiveAnalysisService().analyze(url: url) {
            if wantsJSON {
                return try CLIJSONRenderer.renderDylibs(archiveAnalysis)
            }
            return CLIReportRenderer.renderDylibs(archiveAnalysis)
        }
        let analysis = try DocumentAnalysisService().analyze(url: url)
        if wantsJSON {
            return try CLIJSONRenderer.renderDylibs(analysis)
        }
        return CLIReportRenderer.renderDylibs(analysis)
    }
}

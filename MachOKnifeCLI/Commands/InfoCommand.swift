import Foundation
import MachOKnifeKit

struct InfoCommand {
    static let name = "info"
    static let usage = "machoe-cli info <path> [--json]"

    static func run(arguments: [String]) throws -> String {
        let parsed = try CLICommandSupport.parse(arguments, valueOptions: [], flagOptions: ["--json"], usage: usage)
        let url = try CLICommandSupport.requiredPath(parsed, usage: usage)
        // `--json` 输出稳定键名的 JSON，便于脚本 / CI 解析；默认仍是人类可读文本。
        let wantsJSON = parsed.contains("--json")
        if let archiveAnalysis = try ArchiveAnalysisService().analyze(url: url) {
            if wantsJSON {
                return try CLIJSONRenderer.renderInfo(archiveAnalysis)
            }
            return CLIReportRenderer.renderInfo(archiveAnalysis)
        }
        let analysis = try DocumentAnalysisService().analyze(url: url)
        if wantsJSON {
            return try CLIJSONRenderer.renderInfo(analysis)
        }
        return CLIReportRenderer.renderInfo(analysis)
    }
}

import Foundation
import MachOKnifeKit

struct SplitCommand {
    static let name = "split"
    static let usage = "machoe-cli split <path> --output-dir <path> [--arch <architecture>] [--arch <architecture> ...]"

    static func run(arguments: [String]) throws -> String {
        // `--arch` 允许重复以一次拆出多个架构；`--output-dir` 只能出现一次。
        let parsed = try CLICommandSupport.parse(
            arguments,
            valueOptions: ["--output-dir", "--arch"],
            repeatableOptions: ["--arch"],
            usage: usage
        )
        let inputURL = try CLICommandSupport.requiredPath(parsed, usage: usage)
        let outputDirectory = URL(filePath: try parsed.requiredValue("--output-dir", usage: usage))
        // 去掉重复的 `--arch`（保持首次出现的顺序），避免同一架构被重复导出、输出列表出现重复行。
        var seenArchitectures = Set<String>()
        let architectures = parsed.values("--arch").filter { seenArchitectures.insert($0).inserted }

        let outputs = try MachOMergeSplitService().split(
            inputURL: inputURL,
            architectures: architectures,
            outputDirectoryURL: outputDirectory
        )

        return (["Split outputs:"] + outputs.map(\.path)).joined(separator: "\n") + "\n"
    }
}

import Foundation
import MachOKnifeKit

struct RemoveArchCommand {
    static let name = "remove-arch"
    static let usage = "machoe-cli remove-arch <path> --arch <architecture> [--arch <architecture> ...] (--output <path> | --in-place)"

    static func run(arguments: [String]) throws -> String {
        // `--arch` 可重复以一次移除多个架构；`--output` 与 `--in-place` 二选一。
        let parsed = try CLICommandSupport.parse(
            arguments,
            valueOptions: ["--arch", "--output"],
            flagOptions: ["--in-place"],
            repeatableOptions: ["--arch"],
            usage: usage
        )
        let inputURL = try CLICommandSupport.requiredPath(parsed, usage: usage)

        // 去重并保持首次出现的顺序；至少要指定一个架构，否则命令没有意义。
        var seenArchitectures = Set<String>()
        let architectures = parsed.values("--arch").filter { seenArchitectures.insert($0).inserted }
        guard architectures.isEmpty == false else {
            throw CLIError.invalidUsage(usage, detail: "missing required option '--arch'")
        }

        let outputURL = try resolveOutputURL(parsed, inputURL: inputURL)

        // 服务层先写同目录临时文件再原子替换，因此原地修改（输出 == 输入）也是安全的。
        try MachOMergeSplitService().removeArchitectures(architectures, from: inputURL, outputURL: outputURL)

        let remaining = try MachOMergeSplitService().availableArchitectures(for: outputURL)
        return [
            "Removed: \(architectures.joined(separator: ", "))",
            "Remaining: \(remaining.joined(separator: ", "))",
            "Wrote: \(outputURL.path)",
        ].joined(separator: "\n") + "\n"
    }

    /// 解析输出位置：必须显式给出 `--output <path>` 或 `--in-place` 之一。
    ///
    /// 覆盖输入属于破坏性操作，所以要求用户用 `--in-place` 明确表态；
    /// 若 `--output` 恰好解析到输入文件本身（包括 `..`、符号链接等别名），视为误用并提示改用 `--in-place`，
    /// 与 `merge` 拒绝覆盖输入的约定保持一致。
    private static func resolveOutputURL(_ parsed: CLIParsedArguments, inputURL: URL) throws -> URL {
        let isInPlace = parsed.contains("--in-place")
        if let outputPath = parsed.value("--output") {
            if isInPlace {
                throw CLIError.invalidUsage(usage, detail: "--output cannot be combined with --in-place")
            }
            let outputURL = URL(filePath: outputPath)
            if CLICommandSupport.referToSameFile(inputURL, outputURL) {
                throw CLIError.invalidUsage(
                    usage,
                    detail: "--output must not overwrite the input file; pass --in-place to modify it in place"
                )
            }
            return outputURL
        }

        guard isInPlace else {
            throw CLIError.invalidUsage(usage, detail: "missing required option '--output' (or pass --in-place)")
        }
        return inputURL
    }
}

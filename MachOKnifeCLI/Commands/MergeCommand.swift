import Foundation
import MachOKnifeKit

struct MergeCommand {
    static let name = "merge"
    static let usage = "machoe-cli merge <input1> <input2> [<inputN> ...] --output <path>"

    static func run(arguments: [String]) throws -> String {
        // Inputs may appear before or after --output; every positional argument is an input.
        let parsed = try CLICommandSupport.parse(arguments, valueOptions: ["--output"], usage: usage)
        let outputURL = URL(filePath: try parsed.requiredValue("--output", usage: usage))
        // 合并至少需要两个输入；在这里提前给出用法错误，而不是交给服务层抛出不带用法提示的错误。
        let inputURLs = try CLICommandSupport.requiredURLs(parsed.positionals, minimumCount: 2, usage: usage)

        // 合并服务会先删除已存在的输出文件再调用 lipo；若输出路径恰好是某个输入，
        // 输入文件会在 lipo 读取之前被删掉并永久丢失，因此必须在任何写操作之前拒绝。
        if let overlappingInput = inputURLs.first(where: { CLICommandSupport.referToSameFile($0, outputURL) }) {
            throw CLIError.invalidUsage(
                usage,
                detail: "--output must not overwrite an input file ('\(overlappingInput.path)')"
            )
        }

        try MachOMergeSplitService().merge(inputURLs: inputURLs, outputURL: outputURL)
        return "Merged output: \(outputURL.path)\n"
    }
}

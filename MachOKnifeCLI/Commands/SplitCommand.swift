import Foundation
import MachOKnifeKit

struct SplitCommand {
    static let name = "split"
    static let usage = "machoe-cli split <path> --output-dir <path> [--arch <architecture>] [--arch <architecture> ...]"

    static func run(arguments: [String]) throws -> String {
        let parsed = try CLICommandSupport.parse(arguments, valueOptions: ["--output-dir", "--arch"], usage: usage)
        let inputURL = try CLICommandSupport.requiredPath(parsed, usage: usage)
        let outputDirectory = URL(filePath: try parsed.requiredValue("--output-dir", usage: usage))
        let architectures = parsed.values("--arch")

        let outputs = try MachOMergeSplitService().split(
            inputURL: inputURL,
            architectures: architectures,
            outputDirectoryURL: outputDirectory
        )

        return (["Split outputs:"] + outputs.map(\.path)).joined(separator: "\n") + "\n"
    }
}

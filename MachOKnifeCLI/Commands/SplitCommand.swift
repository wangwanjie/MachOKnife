import Foundation
import MachOKnifeKit

struct SplitCommand {
    static let name = "split"
    static let usage = "machoe-cli split <path> --output-dir <path> [--arch <architecture>] [--arch <architecture> ...]"

    static func run(arguments: [String]) throws -> String {
        let inputURL = try CLICommandSupport.requiredPath(arguments, usage: usage)
        let outputDirectory = URL(filePath: try CLICommandSupport.requiredOption("--output-dir", in: arguments, usage: usage))
        let architectures = CLICommandSupport.repeatedOptions("--arch", in: arguments)

        let outputs = try MachOMergeSplitService().split(
            inputURL: inputURL,
            architectures: architectures,
            outputDirectoryURL: outputDirectory
        )

        return (["Split outputs:"] + outputs.map(\.path)).joined(separator: "\n") + "\n"
    }
}

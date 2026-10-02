import Foundation
import MachOKnifeKit

struct MergeCommand {
    static let name = "merge"
    static let usage = "machoe-cli merge <input1> <input2> [<inputN> ...] --output <path>"

    static func run(arguments: [String]) throws -> String {
        // Inputs may appear before or after --output; every positional argument is an input.
        let parsed = try CLICommandSupport.parse(arguments, valueOptions: ["--output"], usage: usage)
        let outputURL = URL(filePath: try parsed.requiredValue("--output", usage: usage))
        let inputURLs = try CLICommandSupport.requiredURLs(parsed.positionals, usage: usage)

        try MachOMergeSplitService().merge(inputURLs: inputURLs, outputURL: outputURL)
        return "Merged output: \(outputURL.path)\n"
    }
}

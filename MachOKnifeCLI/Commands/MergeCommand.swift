import Foundation
import MachOKnifeKit

struct MergeCommand {
    static let name = "merge"
    static let usage = "machoe-cli merge <input1> <input2> [<inputN> ...] --output <path>"

    static func run(arguments: [String]) throws -> String {
        guard let outputIndex = arguments.firstIndex(of: "--output"), arguments.indices.contains(outputIndex + 1) else {
            throw CLIError.invalidUsage(usage)
        }

        let outputPath = arguments[outputIndex + 1]
        let outputURL = URL(filePath: outputPath)
        let inputPaths = Array(arguments[..<outputIndex])
        let inputURLs = try CLICommandSupport.requiredURLs(inputPaths, usage: usage)

        try MachOMergeSplitService().merge(inputURLs: inputURLs, outputURL: outputURL)
        return "Merged output: \(outputURL.path)\n"
    }
}

import Foundation
import RetagEngine

struct FixDyldCacheDylibCommand {
    static let name = "fix-dyld-cache-dylib"
    static let usage = "machoe-cli fix-dyld-cache-dylib <path> --output <path>"

    static func run(arguments: [String]) throws -> String {
        let inputURL = try CLICommandSupport.requiredPath(arguments, usage: usage)
        let outputURL = URL(filePath: try CLICommandSupport.requiredOption("--output", in: arguments, usage: usage))
        let result = try RetagEngine().fixDyldCacheDylib(inputURL: inputURL, outputURL: outputURL)
        return CLIReportRenderer.renderWrite(outputURL: result.outputURL, diff: result.diff)
    }
}

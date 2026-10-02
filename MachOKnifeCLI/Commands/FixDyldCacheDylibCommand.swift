import Foundation
import RetagEngine

struct FixDyldCacheDylibCommand {
    static let name = "fix-dyld-cache-dylib"
    static let usage = "machoe-cli fix-dyld-cache-dylib <path> --output <path>"

    static func run(arguments: [String]) throws -> String {
        let parsed = try CLICommandSupport.parse(arguments, valueOptions: ["--output"], usage: usage)
        let inputURL = try CLICommandSupport.requiredPath(parsed, usage: usage)
        let outputURL = URL(filePath: try parsed.requiredValue("--output", usage: usage))
        let result = try RetagEngine().fixDyldCacheDylib(inputURL: inputURL, outputURL: outputURL)
        return CLIReportRenderer.renderWrite(outputURL: result.outputURL, diff: result.diff)
    }
}

import Foundation
import RetagEngine

struct RetagPlatformCommand {
    static let name = "retag-platform"
    static let usage = "machoe-cli retag-platform <path> --platform macos|ios|iossim|maccatalyst --min <version> --sdk <version> --output <path>"

    static func run(arguments: [String]) throws -> String {
        let inputURL = try CLICommandSupport.requiredPath(arguments, usage: usage)
        let platform = try CLICommandSupport.parsePlatform(
            CLICommandSupport.requiredOption("--platform", in: arguments, usage: usage),
            usage: usage
        )
        let minimumOS = try CLICommandSupport.parseVersion(
            CLICommandSupport.requiredOption("--min", in: arguments, usage: usage),
            usage: usage
        )
        let sdk = try CLICommandSupport.parseVersion(
            CLICommandSupport.requiredOption("--sdk", in: arguments, usage: usage),
            usage: usage
        )
        let outputURL = URL(filePath: try CLICommandSupport.requiredOption("--output", in: arguments, usage: usage))

        let result = try RetagEngine().retagPlatform(
            inputURL: inputURL,
            outputURL: outputURL,
            platform: platform,
            minimumOS: minimumOS,
            sdk: sdk
        )
        return CLIReportRenderer.renderWrite(outputURL: result.outputURL, diff: result.diff)
    }
}

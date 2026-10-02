import Foundation
import RetagEngine

struct RetagPlatformCommand {
    static let name = "retag-platform"
    static let usage = "machoe-cli retag-platform <path> --platform macos|ios|iossim|maccatalyst --min <version> --sdk <version> --output <path> [--arch <architecture>]"

    static func run(arguments: [String]) throws -> String {
        let parsed = try CLICommandSupport.parse(
            arguments,
            valueOptions: ["--platform", "--min", "--sdk", "--output", "--arch"],
            usage: usage
        )
        let inputURL = try CLICommandSupport.requiredPath(parsed, usage: usage)
        let platform = try CLICommandSupport.parsePlatform(
            parsed.requiredValue("--platform", usage: usage),
            usage: usage
        )
        let minimumOS = try CLICommandSupport.parseVersion(
            parsed.requiredValue("--min", usage: usage),
            usage: usage
        )
        let sdk = try CLICommandSupport.parseVersion(
            parsed.requiredValue("--sdk", usage: usage),
            usage: usage
        )
        let outputURL = URL(filePath: try parsed.requiredValue("--output", usage: usage))
        let architecture = parsed.value("--arch")

        let result = try RetagEngine().retagPlatform(
            inputURL: inputURL,
            outputURL: outputURL,
            platform: platform,
            minimumOS: minimumOS,
            sdk: sdk,
            architecture: architecture
        )
        return CLIReportRenderer.renderWrite(outputURL: result.outputURL, diff: result.diff)
    }
}

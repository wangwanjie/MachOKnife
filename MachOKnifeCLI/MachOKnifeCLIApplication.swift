import Foundation

enum MachOKnifeCLIApplication {
    static func main(arguments: [String] = CommandLine.arguments) {
        do {
            let output = try run(arguments: arguments)
            FileHandle.standardOutput.write(Data(output.utf8))
        } catch let error as CLIError {
            FileHandle.standardError.write(Data("error: \(error.message)\n".utf8))
            Foundation.exit(Int32(error.exitCode))
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    static func run(arguments: [String]) throws -> String {
        guard arguments.count >= 3 else {
            throw CLIError.usage
        }

        let command = arguments[1]
        let commandArguments = Array(arguments.dropFirst(2))

        switch command {
        case SummaryCommand.name:
            return try SummaryCommand.run(arguments: commandArguments)
        case ContaminationCheckCommand.name:
            return try ContaminationCheckCommand.run(arguments: commandArguments)
        case MergeCommand.name:
            return try MergeCommand.run(arguments: commandArguments)
        case SplitCommand.name:
            return try SplitCommand.run(arguments: commandArguments)
        case InfoCommand.name:
            return try InfoCommand.run(arguments: commandArguments)
        case ListDylibsCommand.name:
            return try ListDylibsCommand.run(arguments: commandArguments)
        case RetagPlatformCommand.name:
            return try RetagPlatformCommand.run(arguments: commandArguments)
        case BuildXCFrameworkCommand.name:
            return try BuildXCFrameworkCommand.run(arguments: commandArguments)
        case RewriteRPathCommand.name:
            return try RewriteRPathCommand.run(arguments: commandArguments)
        case FixDyldCacheDylibCommand.name:
            return try FixDyldCacheDylibCommand.run(arguments: commandArguments)
        case SetIDCommand.name:
            return try SetIDCommand.run(arguments: commandArguments)
        case StripSignatureCommand.name:
            return try StripSignatureCommand.run(arguments: commandArguments)
        case ValidateCommand.name:
            return try ValidateCommand.run(arguments: commandArguments)
        default:
            throw CLIError.unsupportedCommand(command)
        }
    }
}

struct CLIError: Error {
    let message: String
    let exitCode: Int

    static let usage = CLIError(
        message: """
        usage:
          machoe-cli summary <path>
          machoe-cli check-contamination <path> --mode platform|architecture --target <value>
          machoe-cli merge <input1> <input2> [<inputN> ...] --output <path>
          machoe-cli split <path> --output-dir <path> [--arch <architecture>] [--arch <architecture> ...]
          machoe-cli info <path>
          machoe-cli list-dylibs <path>
          machoe-cli retag-platform <path> --platform macos|ios|iossim|maccatalyst --min <version> --sdk <version> --output <path>
          machoe-cli build-xcframework --library <path> [--library <path> ...] --headers <path> [--headers <path> ...] --output <path>
          machoe-cli build-xcframework --source-library <path> [--ios-device-source-library <path>] [--ios-simulator-source-library <path>] [--maccatalyst-source-library <path>] --headers-dir <path> (--output <path> | --output-dir <path> [--xcframework-name <name>]) [--output-library-name <name>] [--module-name <name>] [--umbrella-header <name>] [--maccatalyst-min-version <version>] [--maccatalyst-sdk-version <version>]
          machoe-cli rewrite-rpath <path> --from <path> --to <path> --output <path>
          machoe-cli fix-dyld-cache-dylib <path> --output <path>
          machoe-cli set-id <path> --install-name <path> --output <path>
          machoe-cli strip-signature <path> --output <path>
          machoe-cli validate <path>
        """,
        exitCode: 1
    )

    static func unsupportedCommand(_ command: String) -> CLIError {
        CLIError(message: "unsupported command '\(command)'", exitCode: 2)
    }

    static func invalidUsage(_ usage: String) -> CLIError {
        CLIError(message: usage, exitCode: 1)
    }
}

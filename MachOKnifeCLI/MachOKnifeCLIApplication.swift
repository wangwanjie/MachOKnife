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
        guard arguments.count >= 2 else {
            return CLIHelp.text
        }

        let command = arguments[1]
        if CLIHelp.isHelpCommand(command) {
            return CLIHelp.text
        }
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

    static let usage = CLIError(message: CLIHelp.text, exitCode: 1)

    static func unsupportedCommand(_ command: String) -> CLIError {
        CLIError(message: "unsupported command '\(command)'", exitCode: 2)
    }

    static func invalidUsage(_ usage: String) -> CLIError {
        CLIError(message: usage, exitCode: 1)
    }
}

private enum CLIHelp {
    private struct CommandDescriptor {
        let name: String
        let summary: String
        let usageLines: [String]
    }

    private static let author = "VanJay"
    private static let email = "vanjay.dev@gmail.com"
    private static let fallbackVersion = "1.3.0"

    private static let commands = [
        CommandDescriptor(
            name: SummaryCommand.name,
            summary: "Print a concise Mach-O or archive overview.",
            usageLines: [SummaryCommand.usage]
        ),
        CommandDescriptor(
            name: ContaminationCheckCommand.name,
            summary: "Detect platform or architecture slices that do not match a target.",
            usageLines: [ContaminationCheckCommand.usage]
        ),
        CommandDescriptor(
            name: MergeCommand.name,
            summary: "Combine multiple slices or inputs into a single output file.",
            usageLines: [MergeCommand.usage]
        ),
        CommandDescriptor(
            name: SplitCommand.name,
            summary: "Extract one or more architectures into separate output files.",
            usageLines: [SplitCommand.usage]
        ),
        CommandDescriptor(
            name: InfoCommand.name,
            summary: "Inspect Mach-O metadata, slices, and load commands.",
            usageLines: [InfoCommand.usage]
        ),
        CommandDescriptor(
            name: ListDylibsCommand.name,
            summary: "List dylib dependencies and LC_RPATH entries.",
            usageLines: [ListDylibsCommand.usage]
        ),
        CommandDescriptor(
            name: RetagPlatformCommand.name,
            summary: "Rewrite platform, minimum OS, and SDK metadata for a binary.",
            usageLines: [RetagPlatformCommand.usage]
        ),
        CommandDescriptor(
            name: BuildXCFrameworkCommand.name,
            summary: "Package static libraries and headers into an XCFramework.",
            usageLines: BuildXCFrameworkCommand.usage.split(separator: "\n").map(String.init)
        ),
        CommandDescriptor(
            name: RewriteRPathCommand.name,
            summary: "Rewrite matching LC_RPATH entries in a Mach-O binary.",
            usageLines: [RewriteRPathCommand.usage]
        ),
        CommandDescriptor(
            name: FixDyldCacheDylibCommand.name,
            summary: "Normalize dyld cache style dylibs for normal app loading.",
            usageLines: [FixDyldCacheDylibCommand.usage]
        ),
        CommandDescriptor(
            name: SetIDCommand.name,
            summary: "Change the install name of a dylib.",
            usageLines: [SetIDCommand.usage]
        ),
        CommandDescriptor(
            name: StripSignatureCommand.name,
            summary: "Remove the code signature load command from a binary.",
            usageLines: [StripSignatureCommand.usage]
        ),
        CommandDescriptor(
            name: ValidateCommand.name,
            summary: "Validate Mach-O structure and signature metadata.",
            usageLines: [ValidateCommand.usage]
        ),
    ]

    static let text = render()

    static func isHelpCommand(_ command: String) -> Bool {
        command == "help" || command == "-h" || command == "--help"
    }

    private static func render() -> String {
        let header = [
            "machoe-cli v\(version) \(author) \(email)",
            "",
            "Usage:",
            "  machoe-cli <command> [options]",
            "  machoe-cli help",
            "  machoe-cli --help",
            "",
            "Commands:",
        ]

        let commandBlocks = commands.map { descriptor in
            ([ "  \(descriptor.name)",
               "    \(descriptor.summary)" ] + descriptor.usageLines.map { "    \($0)" }).joined(separator: "\n")
        }

        return header.joined(separator: "\n") + "\n" + commandBlocks.joined(separator: "\n\n") + "\n"
    }

    private static var version: String {
        if let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           bundleVersion.isEmpty == false {
            return bundleVersion
        }

        return fallbackVersion
    }
}

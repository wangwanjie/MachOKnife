import Foundation

enum MachOKnifeCLIApplication {
    /// sysexits(3) EX_USAGE: the command was used incorrectly.
    static let usageExitCode: Int32 = 64

    static func main(arguments: [String] = CommandLine.arguments) {
        do {
            let output = try run(arguments: arguments)
            FileHandle.standardOutput.write(Data(output.utf8))
        } catch let failure as CLICommandFailure {
            FileHandle.standardOutput.write(Data(failure.output.utf8))
            if let message = failure.message {
                FileHandle.standardError.write(Data("error: \(message)\n".utf8))
            }
            Foundation.exit(failure.exitCode)
        } catch let error as CLIError {
            let text = error.isRawMessage ? error.message : "error: \(error.message)\n"
            FileHandle.standardError.write(Data(text.utf8))
            Foundation.exit(error.exitCode)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    static func run(arguments: [String]) throws -> String {
        guard arguments.count >= 2 else {
            throw CLIError(message: CLIHelp.text, exitCode: usageExitCode, isRawMessage: true)
        }

        let command = arguments[1]
        let commandArguments = Array(arguments.dropFirst(2))

        if CLIHelp.isVersionCommand(command) {
            return CLIHelp.versionLine + "\n"
        }

        if CLIHelp.isHelpCommand(command) {
            guard let topic = commandArguments.first else {
                return CLIHelp.text
            }
            guard let help = CLIHelp.commandHelp(for: topic) else {
                throw CLIError.unsupportedCommand(topic)
            }
            return help
        }

        if CLICommandSupport.containsHelpFlag(commandArguments) {
            guard let help = CLIHelp.commandHelp(for: command) else {
                throw CLIError.unsupportedCommand(command)
            }
            return help
        }

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
    let exitCode: Int32
    /// When true, `message` is written to stderr verbatim (no `error:` prefix).
    var isRawMessage = false

    static func unsupportedCommand(_ command: String) -> CLIError {
        CLIError(
            message: "unsupported command '\(command)'. Run 'machoe-cli --help' for a list of commands.",
            exitCode: MachOKnifeCLIApplication.usageExitCode
        )
    }

    static func invalidUsage(_ usage: String, detail: String? = nil) -> CLIError {
        var lines: [String] = []
        if let detail {
            lines.append(detail)
        }
        lines.append("usage:")
        lines += usage.split(separator: "\n").map { "  \($0)" }
        return CLIError(message: lines.joined(separator: "\n"), exitCode: MachOKnifeCLIApplication.usageExitCode)
    }
}

/// Thrown when a command produced a normal report but must exit with a non-zero status
/// (for example a contamination check that found mismatches, or a failed validation).
/// The report is still written to stdout.
struct CLICommandFailure: Error {
    let output: String
    let exitCode: Int32
    var message: String?
}

enum CLIHelp {
    private struct CommandDescriptor {
        let name: String
        let summary: String
        let usageLines: [String]
    }

    private static let author = "VanJay"
    private static let email = "vanjay.dev@gmail.com"
    private static let fallbackVersion = "unknown"

    private static let commands = [
        CommandDescriptor(
            name: SummaryCommand.name,
            summary: "Print a concise Mach-O or archive overview.",
            usageLines: [SummaryCommand.usage]
        ),
        CommandDescriptor(
            name: ContaminationCheckCommand.name,
            summary: "Detect platform or architecture slices that do not match a target. Exits with status 1 when mismatches are found.",
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
            summary: "Validate Mach-O structure and signature metadata. Exits with status 1 when problems are found.",
            usageLines: [ValidateCommand.usage]
        ),
    ]

    static let text = render()

    static var versionLine: String {
        "machoe-cli v\(version)"
    }

    static func isHelpCommand(_ command: String) -> Bool {
        command == "help" || command == "-h" || command == "--help"
    }

    static func isVersionCommand(_ command: String) -> Bool {
        command == "--version" || command == "-v" || command == "version"
    }

    static func commandHelp(for name: String) -> String? {
        guard let descriptor = commands.first(where: { $0.name == name }) else {
            return nil
        }
        let lines = [
            "\(descriptor.name): \(descriptor.summary)",
            "",
            "Usage:",
        ] + descriptor.usageLines.map { "  \($0)" }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func render() -> String {
        let header = [
            "\(versionLine) \(author) \(email)",
            "",
            "Usage:",
            "  machoe-cli <command> [options]",
            "  machoe-cli <command> --help",
            "  machoe-cli help [<command>]",
            "  machoe-cli --version",
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
        // The CLI target embeds its generated Info.plist (CREATE_INFOPLIST_SECTION_IN_BINARY),
        // so this reflects MARKETING_VERSION from the project.
        if let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           bundleVersion.isEmpty == false {
            return bundleVersion
        }

        return fallbackVersion
    }
}

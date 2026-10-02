import CoreMachO
import Foundation

/// Result of parsing a command's argument list against a declared set of options.
///
/// Positional arguments are everything that is not an option or an option value. Option
/// values may be given as `--name value` or `--name=value`. A literal `--` ends option
/// parsing; everything after it is positional.
struct CLIParsedArguments {
    let positionals: [String]
    private let optionValues: [String: [String]]
    private let flags: Set<String>

    init(positionals: [String], optionValues: [String: [String]], flags: Set<String>) {
        self.positionals = positionals
        self.optionValues = optionValues
        self.flags = flags
    }

    func value(_ name: String) -> String? {
        optionValues[name]?.first
    }

    func values(_ name: String) -> [String] {
        optionValues[name] ?? []
    }

    func contains(_ name: String) -> Bool {
        optionValues[name] != nil || flags.contains(name)
    }

    func requiredValue(_ name: String, usage: String) throws -> String {
        guard let value = value(name) else {
            throw CLIError.invalidUsage(usage, detail: "missing required option '\(name)'")
        }
        return value
    }
}

enum CLICommandSupport {
    /// Parses `arguments`, rejecting any option that is not declared in `valueOptions` or `flagOptions`.
    static func parse(
        _ arguments: [String],
        valueOptions: Set<String>,
        flagOptions: Set<String> = [],
        usage: String
    ) throws -> CLIParsedArguments {
        var positionals: [String] = []
        var optionValues: [String: [String]] = [:]
        var flags: Set<String> = []
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]
            index += 1

            if argument == "--" {
                positionals.append(contentsOf: arguments[index...])
                break
            }

            guard isOptionToken(argument) else {
                positionals.append(argument)
                continue
            }

            var name = argument
            var inlineValue: String?
            if argument.hasPrefix("--"), let equalsIndex = argument.firstIndex(of: "=") {
                name = String(argument[..<equalsIndex])
                inlineValue = String(argument[argument.index(after: equalsIndex)...])
            }

            if valueOptions.contains(name) {
                let value: String
                if let inlineValue {
                    value = inlineValue
                } else {
                    guard index < arguments.endIndex else {
                        throw CLIError.invalidUsage(usage, detail: "option '\(name)' requires a value")
                    }
                    value = arguments[index]
                    index += 1
                }
                optionValues[name, default: []].append(value)
            } else if flagOptions.contains(name), inlineValue == nil {
                flags.insert(name)
            } else {
                throw CLIError.invalidUsage(usage, detail: "unknown option '\(name)'")
            }
        }

        return CLIParsedArguments(positionals: positionals, optionValues: optionValues, flags: flags)
    }

    /// Returns the single positional input path. Option tokens and option values are never treated as the path.
    static func requiredPath(_ parsed: CLIParsedArguments, usage: String) throws -> URL {
        guard let first = parsed.positionals.first else {
            throw CLIError.invalidUsage(usage, detail: "missing input path")
        }
        guard parsed.positionals.count == 1 else {
            throw CLIError.invalidUsage(usage, detail: "unexpected argument '\(parsed.positionals[1])'")
        }
        return URL(filePath: first)
    }

    static func requiredURLs(_ paths: [String], minimumCount: Int = 1, usage: String) throws -> [URL] {
        guard paths.count >= minimumCount else {
            throw CLIError.invalidUsage(usage, detail: "expected at least \(minimumCount) input path(s)")
        }
        return paths.map { URL(filePath: $0) }
    }

    /// Returns true when `arguments` asks for command help before any `--` terminator.
    static func containsHelpFlag(_ arguments: [String]) -> Bool {
        for argument in arguments {
            if argument == "--" { return false }
            if argument == "--help" || argument == "-h" { return true }
        }
        return false
    }

    static func parseVersion(_ value: String, usage: String) throws -> MachOVersion {
        guard let version = MachOVersionParser.parse(value) else {
            throw CLIError.invalidUsage(usage, detail: "invalid version '\(value)'")
        }
        return version
    }

    static func parsePlatform(_ value: String, usage: String) throws -> MachOPlatform {
        switch value.lowercased() {
        case "macos":
            return .macOS
        case "ios":
            return .iOS
        case "iossim":
            return .iOSSimulator
        case "maccatalyst":
            return .macCatalyst
        default:
            throw CLIError.invalidUsage(usage, detail: "unsupported platform '\(value)'")
        }
    }

    private static func isOptionToken(_ argument: String) -> Bool {
        guard argument.count > 1, argument.hasPrefix("-") else {
            return false
        }
        // Treat negative numbers as values rather than options.
        return Double(argument) == nil
    }
}

/// Strict parser for Mach-O packed versions (`X[.Y[.Z]]`, X ≤ 65535, Y/Z ≤ 255).
enum MachOVersionParser {
    static func parse(_ value: String) -> MachOVersion? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else {
            return nil
        }

        var numbers: [Int] = []
        for part in parts {
            guard part.isEmpty == false,
                  part.count <= 5,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part) else {
                return nil
            }
            numbers.append(number)
        }

        let major = numbers[0]
        let minor = numbers.count > 1 ? numbers[1] : 0
        let patch = numbers.count > 2 ? numbers[2] : 0
        guard major <= 0xFFFF, minor <= 0xFF, patch <= 0xFF else {
            return nil
        }
        return MachOVersion(major: major, minor: minor, patch: patch)
    }
}

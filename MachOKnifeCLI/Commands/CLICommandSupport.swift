import CoreMachO
import Foundation

enum CLICommandSupport {
    static func requiredPath(_ arguments: [String], usage: String) throws -> URL {
        guard let first = arguments.first else {
            throw CLIError.invalidUsage(usage)
        }
        return URL(filePath: first)
    }

    static func requiredOption(_ name: String, in arguments: [String], usage: String) throws -> String {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            throw CLIError.invalidUsage(usage)
        }
        return arguments[index + 1]
    }

    static func parseVersion(_ value: String, usage: String) throws -> MachOVersion {
        let parts = value.split(separator: ".").map(String.init)
        guard parts.count == 2 || parts.count == 3 else {
            throw CLIError.invalidUsage(usage)
        }
        guard let major = Int(parts[0]), let minor = Int(parts[1]) else {
            throw CLIError.invalidUsage(usage)
        }
        let patch = parts.count == 3 ? (Int(parts[2]) ?? -1) : 0
        guard patch >= 0 else {
            throw CLIError.invalidUsage(usage)
        }
        return MachOVersion(major: major, minor: minor, patch: patch)
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
            throw CLIError.invalidUsage(usage)
        }
    }
}

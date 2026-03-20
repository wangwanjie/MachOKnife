import Foundation

public struct MachOVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: MachOVersion, rhs: MachOVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public enum MachOPlatform: Sendable, Equatable {
    case macOS
    case iOS
    case tvOS
    case watchOS
    case bridgeOS
    case macCatalyst
    case iOSSimulator
    case tvOSSimulator
    case watchOSSimulator
    case driverKit
    case visionOS
    case visionOSSimulator
    case firmware
    case sepOS
    case unknown(UInt32)

    init(rawValue: UInt32) {
        switch rawValue {
        case 1:
            self = .macOS
        case 2:
            self = .iOS
        case 3:
            self = .tvOS
        case 4:
            self = .watchOS
        case 5:
            self = .bridgeOS
        case 6:
            self = .macCatalyst
        case 7:
            self = .iOSSimulator
        case 8:
            self = .tvOSSimulator
        case 9:
            self = .watchOSSimulator
        case 10:
            self = .driverKit
        case 11:
            self = .visionOS
        case 12:
            self = .visionOSSimulator
        case 13:
            self = .firmware
        case 14:
            self = .sepOS
        default:
            self = .unknown(rawValue)
        }
    }
}

public struct BuildToolVersionInfo: Sendable {
    public let tool: UInt32
    public let version: MachOVersion
}

public struct BuildVersionInfo: Sendable {
    public let command: UInt32
    public let commandOffset: Int
    public let platform: MachOPlatform
    public let minimumOS: MachOVersion
    public let sdk: MachOVersion
    public let tools: [BuildToolVersionInfo]
}

public struct VersionMinInfo: Sendable {
    public let command: UInt32
    public let commandOffset: Int
    public let platform: MachOPlatform
    public let minimumOS: MachOVersion
    public let sdk: MachOVersion
}

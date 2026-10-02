import CoreMachOC
import Foundation

/// Canonical architecture names shared by the archive inspector, retag engine and tool services.
public enum MachOArchitectureNaming {
    public static let cpuTypeARM64_32: Int32 = 0x0200_000C
    public static let cpuSubtypeX86_64H: Int32 = 8
    public static let cpuSubtypeARM64E: Int32 = 2

    public static func name(cpuType: Int32, cpuSubtype: Int32) -> String {
        let subtype = cpuSubtype & 0x00FF_FFFF

        switch cpuType {
        case CPU_TYPE_ARM64:
            return subtype == cpuSubtypeARM64E ? "arm64e" : "arm64"
        case cpuTypeARM64_32:
            return "arm64_32"
        case CPU_TYPE_X86_64:
            return subtype == cpuSubtypeX86_64H ? "x86_64h" : "x86_64"
        case CPU_TYPE_ARM:
            switch subtype {
            case 6: return "armv6"
            case 9: return "armv7"
            case 10: return "armv7f"
            case 11: return "armv7s"
            case 12: return "armv7k"
            default: return "arm"
            }
        case CPU_TYPE_X86:
            return "i386"
        case CPU_TYPE_POWERPC:
            return "ppc"
        case CPU_TYPE_POWERPC64:
            return "ppc64"
        default:
            return "cputype_\(cpuType)_subtype_\(subtype)"
        }
    }
}

public enum MachOVersionPackingError: LocalizedError, Equatable {
    case componentOutOfRange(MachOVersion)

    public var errorDescription: String? {
        switch self {
        case let .componentOutOfRange(version):
            return "Version \(version) cannot be encoded: major must be 0...65535 and minor/patch must be 0...255."
        }
    }
}

extension MachOVersion {
    /// Encodes the version as `xxxx.yy.zz` nibbles (`major << 16 | minor << 8 | patch`).
    /// Throws when a component does not fit in its field instead of silently corrupting neighbours.
    public func packedValue() throws -> UInt32 {
        guard (0...0xFFFF).contains(major), (0...0xFF).contains(minor), (0...0xFF).contains(patch) else {
            throw MachOVersionPackingError.componentOutOfRange(self)
        }
        return UInt32(major) << 16 | UInt32(minor) << 8 | UInt32(patch)
    }
}

/// Helpers for carrying the input file's POSIX permissions over to rewritten outputs.
/// Outputs written with `Data.write(to:options:.atomic)` otherwise end up with default
/// 0644 permissions, which drops the executable bit of binaries.
public enum MachOFileAttributes {
    /// Returns the POSIX permission bits of `url`, or nil when they cannot be read.
    public static func posixPermissions(of url: URL, fileManager: FileManager = .default) -> Int? {
        (try? fileManager.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
    }

    /// Applies previously captured permission bits to `url`. Does nothing for nil.
    public static func setPosixPermissions(_ permissions: Int?, on url: URL, fileManager: FileManager = .default) throws {
        guard let permissions else { return }
        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    /// Copies the POSIX permission bits of `sourceURL` onto `destinationURL`.
    /// When the output replaces the input in place, capture the permissions with
    /// `posixPermissions(of:)` before writing instead.
    public static func copyPermissions(from sourceURL: URL, to destinationURL: URL, fileManager: FileManager = .default) throws {
        try setPosixPermissions(posixPermissions(of: sourceURL, fileManager: fileManager), on: destinationURL, fileManager: fileManager)
    }
}

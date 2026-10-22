import CoreMachO
import Foundation
import MachOKnifeKit

enum CLIReportRenderer {
    static func renderInfo(_ analysis: DocumentAnalysis) -> String {
        var lines = [String]()
        lines.append("File: \(analysis.fileURL.path)")
        lines.append("Container: \(containerLabel(for: analysis.containerKind))")
        lines.append("Slices: \(analysis.slices.count)")

        for (index, slice) in analysis.slices.enumerated() {
            lines.append("Slice \(index):")
            // 补充架构、文件类型与 UUID：以前 info 只给出偏移，用户无法区分 fat 文件中的各个切片。
            lines.append("  Architecture: \(MachOArchitectureNaming.name(cpuType: slice.header.cpuType, cpuSubtype: slice.header.cpuSubtype))")
            lines.append("  File Type: \(fileTypeLabel(slice.header.fileType))")
            lines.append("  Offset: \(slice.fileOffset)")
            lines.append("  64-bit: \(slice.is64Bit ? "yes" : "no")")
            if let uuid = slice.uuid {
                lines.append("  UUID: \(uuid.uuidString)")
            }
            lines.append("  Platform: \(platformLabel(slice.platform))")
            lines.append("  Min OS: \(versionLabel(slice.minimumOS))")
            lines.append("  SDK: \(versionLabel(slice.sdkVersion))")
            lines.append("  Load Commands: \(slice.loadCommandCount)")
            if let installName = slice.installName {
                lines.append("  Install Name: \(installName)")
            }
            lines.append("  Dylibs: \(slice.dylibReferences.count)")
            lines.append("  RPaths: \(slice.rpaths.count)")
            lines.append("  Code Signature: \(slice.hasCodeSignature ? "present" : "absent")")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func renderInfo(_ analysis: ArchiveAnalysis) -> String {
        var lines = [String]()
        lines.append("File: \(analysis.fileURL.path)")
        lines.append("Container: \(archiveContainerLabel(for: analysis.kind))")
        lines.append("Architectures: \(analysis.architectures.map(\.architecture).joined(separator: ", "))")

        for architecture in analysis.architectures {
            lines.append("Architecture \(architecture.architecture):")
            lines.append("  Members: \(architecture.memberCount)")
            lines.append("  Parsed Members: \(architecture.parsedMemberCount)")
            lines.append("  Platforms: \(joinedValues(architecture.platforms))")
            lines.append("  Min OS: \(joinedValues(architecture.minimumOSVersions))")
            lines.append("  SDK: \(joinedValues(architecture.sdkVersions))")
            lines.append("  Install Names: \(architecture.installNames.count)")
            lines.append("  Dylibs: \(architecture.dylibReferences.count)")
            lines.append("  RPaths: \(architecture.rpaths.count)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func renderDylibs(_ analysis: DocumentAnalysis) -> String {
        var lines = [String]()
        lines.append("File: \(analysis.fileURL.path)")

        for (index, slice) in analysis.slices.enumerated() {
            lines.append("Slice \(index):")
            if let installName = slice.installName {
                lines.append("  ID: \(installName)")
            }

            for dylib in slice.dylibReferences {
                lines.append("  DYLIB \(dylib.path)")
            }

            for rpath in slice.rpaths {
                lines.append("  RPATH \(rpath)")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func renderDylibs(_ analysis: ArchiveAnalysis) -> String {
        var lines = [String]()
        lines.append("File: \(analysis.fileURL.path)")
        lines.append("Container: \(archiveContainerLabel(for: analysis.kind))")

        for architecture in analysis.architectures {
            lines.append("Architecture \(architecture.architecture):")

            if architecture.installNames.isEmpty == false {
                for installName in architecture.installNames {
                    lines.append("  ID: \(installName)")
                }
            }

            if architecture.dylibReferences.isEmpty, architecture.rpaths.isEmpty {
                lines.append("  No dylib or RPATH entries found.")
                continue
            }

            for dylib in architecture.dylibReferences {
                lines.append("  DYLIB \(dylib)")
            }

            for rpath in architecture.rpaths {
                lines.append("  RPATH \(rpath)")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func renderValidation(_ analysis: DocumentAnalysis, report: CLIValidationReport) -> String {
        var lines = [String]()
        if report.errors.isEmpty {
            lines.append(report.warnings.isEmpty ? "Validation: OK" : "Validation: OK (\(report.warnings.count) warning(s))")
        } else {
            lines.append("Validation: FAILED (\(report.errors.count) error(s), \(report.warnings.count) warning(s))")
        }
        lines.append("File: \(analysis.fileURL.path)")
        for error in report.errors {
            lines.append("Error: \(error)")
        }
        for warning in report.warnings {
            lines.append("Warning: \(warning)")
        }

        for (index, slice) in analysis.slices.enumerated() {
            lines.append("Slice \(index):")
            lines.append("  Platform: \(platformLabel(slice.platform))")
            lines.append("  Min OS: \(versionLabel(slice.minimumOS))")
            lines.append("  SDK: \(versionLabel(slice.sdkVersion))")
            lines.append("  Code Signature: \(slice.hasCodeSignature ? "present" : "absent")")
            lines.append("  Dylibs: \(slice.dylibReferences.count)")
            lines.append("  RPaths: \(slice.rpaths.count)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func renderWrite(outputURL: URL, diff: MachODiff) -> String {
        var lines = [String]()
        lines.append("Wrote: \(outputURL.path)")
        lines.append("Changes: \(diff.entries.count)")

        for entry in diff.entries {
            lines.append("  \(kindLabel(entry.kind)): \(entry.originalValue ?? "(none)") -> \(entry.updatedValue ?? "(removed)")")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func containerLabel(for kind: MachOContainer.Kind) -> String {
        switch kind {
        case .thin:
            return "thin"
        case .fat:
            return "fat"
        }
    }

    static func archiveContainerLabel(for kind: ArchiveContainerKind) -> String {
        switch kind {
        case .archive:
            return "archive"
        case .fatArchive:
            return "fat archive"
        }
    }

    static func platformLabel(_ platform: MachOPlatform?) -> String {
        guard let platform else {
            return "unknown"
        }
        return platformLabel(platform)
    }

    static func platformLabel(_ platform: MachOPlatform) -> String {
        switch platform {
        case .macOS:
            return "macOS"
        case .iOS:
            return "iOS"
        case .tvOS:
            return "tvOS"
        case .watchOS:
            return "watchOS"
        case .bridgeOS:
            return "bridgeOS"
        case .macCatalyst:
            return "Mac Catalyst"
        case .iOSSimulator:
            return "iOS Simulator"
        case .tvOSSimulator:
            return "tvOS Simulator"
        case .watchOSSimulator:
            return "watchOS Simulator"
        case .driverKit:
            return "DriverKit"
        case .visionOS:
            return "visionOS"
        case .visionOSSimulator:
            return "visionOS Simulator"
        case .firmware:
            return "firmware"
        case .sepOS:
            return "sepOS"
        case let .unknown(value):
            return "unknown(\(value))"
        }
    }

    /// Mach-O 头部 filetype 的可读名称（取值见 <mach-o/loader.h> 的 MH_*）。
    static func fileTypeLabel(_ fileType: UInt32) -> String {
        switch fileType {
        case 0x1:
            return "object"
        case 0x2:
            return "execute"
        case 0x3:
            return "fvmlib"
        case 0x4:
            return "core"
        case 0x5:
            return "preload"
        case 0x6:
            return "dylib"
        case 0x7:
            return "dylinker"
        case 0x8:
            return "bundle"
        case 0x9:
            return "dylib_stub"
        case 0xA:
            return "dsym"
        case 0xB:
            return "kext_bundle"
        case 0xC:
            return "fileset"
        default:
            return "unknown(0x\(String(fileType, radix: 16)))"
        }
    }

    /// 依赖库加载命令的类型名称，用于区分普通 / 弱链接 / 重导出等依赖。
    static func dylibKindLabel(_ command: UInt32) -> String {
        switch command {
        case 0xC:
            return "load"
        case 0x8000_0018:
            return "weak"
        case 0x8000_001F:
            return "reexport"
        case 0x20:
            return "lazy"
        case 0x8000_0023:
            return "upward"
        default:
            return "unknown(0x\(String(command, radix: 16)))"
        }
    }

    private static func versionLabel(_ version: MachOVersion?) -> String {
        version?.description ?? "unknown"
    }

    private static func joinedValues(_ values: [String]) -> String {
        values.isEmpty ? "unknown" : values.joined(separator: ", ")
    }

    private static func kindLabel(_ kind: DiffEntry.Kind) -> String {
        switch kind {
        case .installName:
            return "INSTALL_NAME"
        case .dylib:
            return "DYLIB"
        case .rpath:
            return "RPATH"
        case .platform:
            return "PLATFORM"
        case .segmentProtection:
            return "SEGMENT"
        case .codeSignature:
            return "CODE_SIGNATURE"
        }
    }
}

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
            lines.append("  Offset: \(slice.fileOffset)")
            lines.append("  64-bit: \(slice.is64Bit ? "yes" : "no")")
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

    static func renderValidation(_ analysis: DocumentAnalysis) -> String {
        var lines = [String]()
        lines.append("Validation: OK")
        lines.append("File: \(analysis.fileURL.path)")

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

    private static func containerLabel(for kind: MachOContainer.Kind) -> String {
        switch kind {
        case .thin:
            return "thin"
        case .fat:
            return "fat"
        }
    }

    private static func archiveContainerLabel(for kind: ArchiveContainerKind) -> String {
        switch kind {
        case .archive:
            return "archive"
        case .fatArchive:
            return "fat archive"
        }
    }

    private static func platformLabel(_ platform: MachOPlatform?) -> String {
        guard let platform else { return "unknown" }
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

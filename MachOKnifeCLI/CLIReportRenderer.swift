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
            lines.append("  Load Commands: \(slice.loadCommandCount)")
            if let installName = slice.installName {
                lines.append("  Install Name: \(installName)")
            }
            lines.append("  Dylibs: \(slice.dylibReferences.count)")
            lines.append("  RPaths: \(slice.rpaths.count)")
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

    private static func containerLabel(for kind: MachOContainer.Kind) -> String {
        switch kind {
        case .thin:
            return "thin"
        case .fat:
            return "fat"
        }
    }
}

import CoreMachO
import Foundation

/// An archive member that belongs to one architecture of a static library.
struct ArchiveArchitectureMember {
    let name: String
    /// Slices of the member that match the architecture. Nil when the member is not a Mach-O.
    let slices: [CoreMachO.MachOSlice]?
}

/// Collects the members of a static library that belong to a single architecture.
///
/// Members are extracted with indexed file names so duplicate member names (common in
/// real-world archives) are all inspected instead of overwriting each other. For thin
/// archives that mix objects of several architectures, only members whose slices match
/// `architecture` are returned; non-Mach-O members are attributed to the architecture only
/// when the archive has a single architecture.
enum ArchiveArchitectureMembers {
    static func collect(
        architecture: String,
        in archiveURL: URL,
        inspection: ArchiveInspection,
        archiveInspector: ArchiveInspector = ArchiveInspector(),
        fileManager: FileManager = .default
    ) throws -> [ArchiveArchitectureMember] {
        let extraction = try archiveInspector.extractThinArchive(
            url: archiveURL,
            preferredArchitecture: inspection.kind == .fatArchive ? architecture : nil
        )
        defer { try? fileManager.removeItem(at: extraction.archiveURL.deletingLastPathComponent()) }

        let membersDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MachOKnifeArchiveMembers-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: membersDirectory) }

        let extractedMembers = try archiveInspector.extractIndexedMembers(from: extraction.archiveURL, to: membersDirectory)
            .filter { $0.isSymbolTable == false }

        let filtersByArchitecture = inspection.kind == .archive
            && Set(inspection.architectures.filter { $0 != "unknown" }).count > 1

        return extractedMembers.compactMap { member in
            guard let container = try? MachOContainer.parse(at: member.fileURL), container.slices.isEmpty == false else {
                return filtersByArchitecture ? nil : ArchiveArchitectureMember(name: member.name, slices: nil)
            }

            guard filtersByArchitecture else {
                return ArchiveArchitectureMember(name: member.name, slices: container.slices)
            }

            let matchingSlices = container.slices.filter {
                MachOArchitectureNaming.name(cpuType: $0.header.cpuType, cpuSubtype: $0.header.cpuSubtype) == architecture
            }
            guard matchingSlices.isEmpty == false else {
                return nil
            }
            return ArchiveArchitectureMember(name: member.name, slices: matchingSlices)
        }
    }
}

/// Sorts dotted version strings numerically ("9.0" before "10.0"), falling back to
/// lexical order for strings that are not plain dotted numbers.
func numericallySortedVersions<S: Sequence>(_ versions: S) -> [String] where S.Element == String {
    func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == parts.count && numbers.isEmpty == false ? numbers : nil
    }

    return Array(Set(versions)).sorted { lhs, rhs in
        switch (components(lhs), components(rhs)) {
        case let (left?, right?):
            let width = max(left.count, right.count)
            let paddedLeft = left + Array(repeating: 0, count: width - left.count)
            let paddedRight = right + Array(repeating: 0, count: width - right.count)
            if paddedLeft != paddedRight {
                return paddedLeft.lexicographicallyPrecedes(paddedRight)
            }
            return lhs < rhs
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return lhs < rhs
        }
    }
}

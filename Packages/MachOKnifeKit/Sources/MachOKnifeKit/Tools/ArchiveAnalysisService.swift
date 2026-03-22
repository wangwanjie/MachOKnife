import CoreMachO
import Foundation

public struct ArchiveAnalysis: Sendable {
    public let fileURL: URL
    public let kind: ArchiveContainerKind
    public let architectures: [ArchiveArchitectureAnalysis]

    public init(fileURL: URL, kind: ArchiveContainerKind, architectures: [ArchiveArchitectureAnalysis]) {
        self.fileURL = fileURL
        self.kind = kind
        self.architectures = architectures
    }
}

public struct ArchiveArchitectureAnalysis: Sendable {
    public let architecture: String
    public let memberCount: Int
    public let parsedMemberCount: Int
    public let platforms: [String]
    public let minimumOSVersions: [String]
    public let sdkVersions: [String]
    public let installNames: [String]
    public let dylibReferences: [String]
    public let rpaths: [String]

    public init(
        architecture: String,
        memberCount: Int,
        parsedMemberCount: Int,
        platforms: [String],
        minimumOSVersions: [String],
        sdkVersions: [String],
        installNames: [String],
        dylibReferences: [String],
        rpaths: [String]
    ) {
        self.architecture = architecture
        self.memberCount = memberCount
        self.parsedMemberCount = parsedMemberCount
        self.platforms = platforms
        self.minimumOSVersions = minimumOSVersions
        self.sdkVersions = sdkVersions
        self.installNames = installNames
        self.dylibReferences = dylibReferences
        self.rpaths = rpaths
    }
}

public struct ArchiveAnalysisService {
    private let archiveInspector: ArchiveInspector
    private let fileManager: FileManager

    public init(
        archiveInspector: ArchiveInspector = ArchiveInspector(),
        fileManager: FileManager = .default
    ) {
        self.archiveInspector = archiveInspector
        self.fileManager = fileManager
    }

    public func analyze(url: URL) throws -> ArchiveAnalysis? {
        guard let inspection = try archiveInspector.inspect(url: url) else {
            return nil
        }

        let architectures = inspection.architectures.isEmpty ? ["unknown"] : inspection.architectures
        let details = try architectures.map { architecture in
            try analyzeArchitecture(
                architecture,
                in: url,
                inspection: inspection
            )
        }

        return ArchiveAnalysis(fileURL: url, kind: inspection.kind, architectures: details)
    }

    private func analyzeArchitecture(
        _ architecture: String,
        in archiveURL: URL,
        inspection: ArchiveInspection
    ) throws -> ArchiveArchitectureAnalysis {
        let extraction = try archiveInspector.extractThinArchive(
            url: archiveURL,
            preferredArchitecture: inspection.kind == .fatArchive ? architecture : nil
        )
        defer { try? fileManager.removeItem(at: extraction.archiveURL.deletingLastPathComponent()) }

        let membersDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MachOKnifeArchiveAnalysis-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: membersDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: membersDirectory) }

        let members = try archiveInspector.listMembers(in: extraction.archiveURL)
            .filter { !$0.hasPrefix("__.SYMDEF") && $0 != "/" && $0 != "//" }
        try archiveInspector.extractMembers(from: extraction.archiveURL, to: membersDirectory)

        var parsedMemberCount = 0
        var platforms = Set<String>()
        var minimumOSVersions = Set<String>()
        var sdkVersions = Set<String>()
        var installNames = Set<String>()
        var dylibReferences = Set<String>()
        var rpaths = Set<String>()

        for member in members {
            let memberURL = membersDirectory.appendingPathComponent(member)
            guard let container = try? MachOContainer.parse(at: memberURL) else {
                continue
            }

            parsedMemberCount += 1
            for slice in container.slices {
                if let platform = slice.buildVersion?.platform ?? slice.versionMin?.platform {
                    platforms.insert(platformLabel(platform))
                }
                if let minimumOS = slice.buildVersion?.minimumOS ?? slice.versionMin?.minimumOS {
                    minimumOSVersions.insert(minimumOS.description)
                }
                if let sdk = slice.buildVersion?.sdk ?? slice.versionMin?.sdk {
                    sdkVersions.insert(sdk.description)
                }
                if let installName = slice.installName, installName.isEmpty == false {
                    installNames.insert(installName)
                }
                dylibReferences.formUnion(slice.dylibReferences.map(\.path))
                rpaths.formUnion(slice.rpaths)
            }
        }

        return ArchiveArchitectureAnalysis(
            architecture: architecture,
            memberCount: members.count,
            parsedMemberCount: parsedMemberCount,
            platforms: platforms.sorted(),
            minimumOSVersions: minimumOSVersions.sorted(),
            sdkVersions: sdkVersions.sorted(),
            installNames: installNames.sorted(),
            dylibReferences: dylibReferences.sorted(),
            rpaths: rpaths.sorted()
        )
    }

    private func platformLabel(_ platform: MachOPlatform) -> String {
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
}

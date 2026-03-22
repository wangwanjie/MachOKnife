import CoreMachO
import Foundation
import MachO

public struct ToolReportSection: Sendable {
    public let title: String
    public let lines: [String]

    public init(title: String, lines: [String]) {
        self.title = title
        self.lines = lines
    }
}

public struct ToolTextReport: Sendable {
    public let title: String
    public let summaryLines: [String]
    public let sections: [ToolReportSection]

    public init(title: String, summaryLines: [String], sections: [ToolReportSection]) {
        self.title = title
        self.summaryLines = summaryLines
        self.sections = sections
    }

    public var renderedText: String {
        var blocks = [title]

        if summaryLines.isEmpty == false {
            blocks.append(summaryLines.joined(separator: "\n"))
        }

        for section in sections where section.lines.isEmpty == false {
            blocks.append("\(section.title)\n\(String(repeating: "-", count: max(6, section.title.count)))\n\(section.lines.joined(separator: "\n"))")
        }

        return blocks.joined(separator: "\n\n")
    }
}

public enum BinaryContaminationCheckMode: String, CaseIterable, Sendable {
    case platform
    case architecture
}

public struct BinaryContaminationReport: Sendable {
    public let mode: BinaryContaminationCheckMode
    public let target: String
    public let okCount: Int
    public let mismatchCount: Int
    public let uncheckedCount: Int
    public let textReport: ToolTextReport

    public init(
        mode: BinaryContaminationCheckMode,
        target: String,
        okCount: Int,
        mismatchCount: Int,
        uncheckedCount: Int,
        textReport: ToolTextReport
    ) {
        self.mode = mode
        self.target = target
        self.okCount = okCount
        self.mismatchCount = mismatchCount
        self.uncheckedCount = uncheckedCount
        self.textReport = textReport
    }

    public var renderedText: String { textReport.renderedText }
}

public enum MachOToolServiceError: LocalizedError {
    case noSupportedBinary(URL)
    case ambiguousPackage(URL, count: Int)
    case unsupportedInput(URL)
    case noArchitectures(URL)
    case mergeNeedsMultipleInputs
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .noSupportedBinary(url):
            return "No supported Mach-O or archive was found at \(url.path)."
        case let .ambiguousPackage(url, count):
            return "Found \(count) supported binaries inside \(url.path). Choose a single binary or framework."
        case let .unsupportedInput(url):
            return "Unsupported input: \(url.path)"
        case let .noArchitectures(url):
            return "No architectures were detected for \(url.lastPathComponent)."
        case .mergeNeedsMultipleInputs:
            return "Choose at least two input files to merge."
        case let .processFailed(message):
            return message
        }
    }
}

public final class BinarySummaryService {
    private let archiveInspector = ArchiveInspector()
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func makeReport(for url: URL) throws -> ToolTextReport {
        let inputs = try resolveInputs(at: url)
        guard inputs.isEmpty == false else {
            throw MachOToolServiceError.noSupportedBinary(url)
        }

        if inputs.count == 1, let input = inputs.first {
            return try makeSingleReport(for: input)
        }

        let sections = try inputs.map { input in
            let report = try makeSingleReport(for: input)
            var lines = report.summaryLines
            for section in report.sections where section.lines.isEmpty == false {
                lines.append("\(section.title):")
                lines.append(contentsOf: section.lines.map { "  \($0)" })
            }
            return ToolReportSection(title: report.title, lines: lines)
        }

        return ToolTextReport(
            title: url.lastPathComponent,
            summaryLines: [
                "Path: \(url.path)",
                "Detected Binaries: \(inputs.count)",
            ],
            sections: sections
        )
    }

    private func makeSingleReport(for input: ResolvedBinaryInput) throws -> ToolTextReport {
        if let archiveInspection = try archiveInspector.inspect(url: input.binaryURL) {
            let details = try archiveArchitectureDetails(for: input.binaryURL, inspection: archiveInspection)
            let summaryLines = [
                "Path: \(input.originalURL.path)",
                input.originalURL == input.binaryURL ? nil : "Resolved Binary: \(input.binaryURL.path)",
                "Kind: \(archiveInspection.kind == .fatArchive ? "Fat Archive" : "Static Archive")",
                "Architectures: \(details.map(\.architecture).joined(separator: ", "))",
            ].compactMap { $0 }

            let sections = details.map { detail in
                ToolReportSection(
                    title: detail.architecture,
                    lines: [
                        "Members: \(detail.memberCount)",
                        "Platforms: \(detail.platforms.isEmpty ? "unknown" : detail.platforms.joined(separator: ", "))",
                        "Minimum OS: \(detail.minimumOSVersions.isEmpty ? "unknown" : detail.minimumOSVersions.joined(separator: ", "))",
                        "SDK: \(detail.sdkVersions.isEmpty ? "unknown" : detail.sdkVersions.joined(separator: ", "))",
                        "Sample Object: \(detail.sampleMember ?? "none")",
                    ]
                )
            }

            return ToolTextReport(
                title: input.displayName,
                summaryLines: summaryLines,
                sections: sections
            )
        }

        let container = try MachOContainer.parse(at: input.binaryURL)
        let sliceDetails = container.slices.map { slice in
            let architecture = architectureName(cpuType: slice.header.cpuType, cpuSubtype: slice.header.cpuSubtype)
            let platform = platformIdentifier(for: slice.buildVersion?.platform ?? slice.versionMin?.platform)
            return ToolReportSection(
                title: architecture,
                lines: [
                    "Platform: \(platform ?? "unknown")",
                    "Minimum OS: \(slice.buildVersion?.minimumOS.description ?? slice.versionMin?.minimumOS.description ?? "unknown")",
                    "SDK: \(slice.buildVersion?.sdk.description ?? slice.versionMin?.sdk.description ?? "unknown")",
                    "CPU Type: \(cpuTypeDescription(slice.header.cpuType)) (\(slice.header.cpuType))",
                    "CPU Subtype: \(cpuSubtypeDescription(slice.header.cpuSubtype)) (\(slice.header.cpuSubtype))",
                    "File Type: \(fileTypeDescription(slice.header.fileType)) (\(slice.header.fileType))",
                    "Slice Offset: \(slice.offset)",
                    "Load Commands: \(slice.loadCommands.count)",
                    "Segments: \(slice.segments.count)",
                    "Symbols: \(slice.symbols.count)",
                ]
            )
        }

        let summaryLines = [
            "Path: \(input.originalURL.path)",
            input.originalURL == input.binaryURL ? nil : "Resolved Binary: \(input.binaryURL.path)",
            "Kind: \(container.kind == .fat ? "Fat Mach-O" : "Mach-O")",
            "Architectures: \(sliceDetails.map(\.title).joined(separator: ", "))",
        ].compactMap { $0 }

        return ToolTextReport(
            title: input.displayName,
            summaryLines: summaryLines,
            sections: sliceDetails
        )
    }

    private func resolveInputs(at url: URL) throws -> [ResolvedBinaryInput] {
        if url.hasDirectoryPath {
            if url.pathExtension.lowercased() == "framework" {
                return [try ResolvedBinaryInput(
                    originalURL: url,
                    binaryURL: findFrameworkBinary(in: url),
                    displayName: url.lastPathComponent
                )]
            }

            let binaries = try collectSupportedFiles(in: url)
            return binaries.map {
                ResolvedBinaryInput(
                    originalURL: $0,
                    binaryURL: $0,
                    displayName: relativePath(for: $0, rootURL: url)
                )
            }
        }

        return [ResolvedBinaryInput(originalURL: url, binaryURL: url, displayName: url.lastPathComponent)]
    }

    private func collectSupportedFiles(in directoryURL: URL) throws -> [URL] {
        let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var urls = [URL]()
        while let fileURL = enumerator?.nextObject() as? URL {
            guard try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }
            if isSupportedBinary(fileURL) {
                urls.append(fileURL)
            }
        }
        return urls.sorted { relativePath(for: $0, rootURL: directoryURL) < relativePath(for: $1, rootURL: directoryURL) }
    }

    private func isSupportedBinary(_ url: URL) -> Bool {
        if (try? archiveInspector.inspect(url: url)) != nil {
            return true
        }
        return (try? MachOContainer.parse(at: url)) != nil
    }

    private func findFrameworkBinary(in frameworkURL: URL) throws -> URL {
        let frameworkName = frameworkURL.deletingPathExtension().lastPathComponent
        let directBinary = frameworkURL.appendingPathComponent(frameworkName)
        if fileManager.fileExists(atPath: directBinary.path) {
            return directBinary
        }

        let enumerator = fileManager.enumerator(
            at: frameworkURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }
            if isSupportedBinary(fileURL) {
                return fileURL
            }
        }

        throw MachOToolServiceError.noSupportedBinary(frameworkURL)
    }

    private func archiveArchitectureDetails(
        for archiveURL: URL,
        inspection: ArchiveInspection
    ) throws -> [ArchiveArchitectureDetail] {
        let architectures = inspection.architectures.isEmpty ? ["unknown"] : inspection.architectures
        return try architectures.map { architecture in
            let extraction = try archiveInspector.extractThinArchive(
                url: archiveURL,
                preferredArchitecture: inspection.kind == .fatArchive ? architecture : nil
            )
            defer { try? fileManager.removeItem(at: extraction.archiveURL.deletingLastPathComponent()) }

            let membersDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("MachOKnifeSummary-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: membersDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: membersDirectory) }

            let members = try archiveInspector.listMembers(in: extraction.archiveURL)
                .filter { !$0.hasPrefix("__.SYMDEF") && $0 != "/" && $0 != "//" }
            try archiveInspector.extractMembers(from: extraction.archiveURL, to: membersDirectory)

            let inspectedMembers = members.compactMap { memberName -> ArchiveMemberMetadata? in
                let memberURL = membersDirectory.appendingPathComponent(memberName)
                guard let container = try? MachOContainer.parse(at: memberURL), let slice = container.slices.first else {
                    return nil
                }
                return ArchiveMemberMetadata(
                    name: memberName,
                    platform: platformIdentifier(for: slice.buildVersion?.platform ?? slice.versionMin?.platform),
                    minimumOS: slice.buildVersion?.minimumOS.description ?? slice.versionMin?.minimumOS.description,
                    sdk: slice.buildVersion?.sdk.description ?? slice.versionMin?.sdk.description
                )
            }

            return ArchiveArchitectureDetail(
                architecture: architecture,
                memberCount: members.count,
                platforms: Array(Set(inspectedMembers.compactMap(\.platform))).sorted(),
                minimumOSVersions: Array(Set(inspectedMembers.compactMap(\.minimumOS))).sorted(),
                sdkVersions: Array(Set(inspectedMembers.compactMap(\.sdk))).sorted(),
                sampleMember: inspectedMembers.first?.name ?? members.first
            )
        }
    }
}

public final class BinaryContaminationCheckService {
    private let archiveInspector = ArchiveInspector()
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func runCheck(at url: URL, target: String, mode: BinaryContaminationCheckMode) throws -> BinaryContaminationReport {
        let normalizedTarget = mode == .platform
            ? normalizedPlatformTarget(target)
            : target.lowercased()
        let units = try collectInspectionUnits(at: url)
        guard units.isEmpty == false else {
            throw MachOToolServiceError.noSupportedBinary(url)
        }

        var okUnits = [InspectionUnit]()
        var mismatches = [String]()
        var unchecked = [String]()

        for unit in units {
            let values = mode == .platform ? unit.platforms : unit.architectures.map { $0.lowercased() }
            guard values.isEmpty == false else {
                unchecked.append("⚠ \(unit.label): unable to detect \(mode == .platform ? "platform" : "architecture")")
                continue
            }

            let matchesTarget = values.contains(normalizedTarget)
            if matchesTarget && values.count == 1 {
                okUnits.append(unit)
            } else {
                let foundValue = values.sorted().joined(separator: ", ")
                let noun = mode == .platform ? "platforms" : "architectures"
                mismatches.append("✗ \(unit.label): expected \(normalizedTarget), found \(noun) [\(foundValue)]")
            }
        }

        let summaryLines = [
            "Path: \(url.path)",
            "Mode: \(mode == .platform ? "platform" : "architecture")",
            "Target: \(normalizedTarget)",
            "OK: \(okUnits.count)",
            "Mismatches: \(mismatches.count)",
            "Unchecked: \(unchecked.count)",
        ]

        var sections = [ToolReportSection]()
        if mismatches.isEmpty == false {
            sections.append(ToolReportSection(title: "Mismatches", lines: mismatches))
        }
        if unchecked.isEmpty == false {
            sections.append(ToolReportSection(title: "Unchecked", lines: unchecked))
        }
        if okUnits.isEmpty == false {
            sections.append(
                ToolReportSection(
                    title: "Matched",
                    lines: okUnits.map { "✓ \($0.label)" }
                )
            )
        }

        return BinaryContaminationReport(
            mode: mode,
            target: normalizedTarget,
            okCount: okUnits.count,
            mismatchCount: mismatches.count,
            uncheckedCount: unchecked.count,
            textReport: ToolTextReport(
                title: url.lastPathComponent,
                summaryLines: summaryLines,
                sections: sections
            )
        )
    }

    private func collectInspectionUnits(at url: URL) throws -> [InspectionUnit] {
        if url.hasDirectoryPath {
            if url.pathExtension.lowercased() == "framework" {
                let binaryURL = try findFrameworkBinary(in: url)
                return try inspectionUnits(for: binaryURL, rootURL: url.deletingLastPathComponent())
            }
            let supportedFiles = try collectSupportedFiles(in: url)
            return try supportedFiles.flatMap { try inspectionUnits(for: $0, rootURL: url) }
        }
        return try inspectionUnits(for: url, rootURL: url.deletingLastPathComponent())
    }

    private func collectSupportedFiles(in directoryURL: URL) throws -> [URL] {
        let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var urls = [URL]()
        while let fileURL = enumerator?.nextObject() as? URL {
            guard try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }
            if isSupportedBinary(fileURL) {
                urls.append(fileURL)
            }
        }
        return urls.sorted { relativePath(for: $0, rootURL: directoryURL) < relativePath(for: $1, rootURL: directoryURL) }
    }

    private func isSupportedBinary(_ url: URL) -> Bool {
        if (try? archiveInspector.inspect(url: url)) != nil {
            return true
        }
        return (try? MachOContainer.parse(at: url)) != nil
    }

    private func findFrameworkBinary(in frameworkURL: URL) throws -> URL {
        let frameworkName = frameworkURL.deletingPathExtension().lastPathComponent
        let directBinary = frameworkURL.appendingPathComponent(frameworkName)
        if fileManager.fileExists(atPath: directBinary.path) {
            return directBinary
        }

        let enumerator = fileManager.enumerator(
            at: frameworkURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }
            if isSupportedBinary(fileURL) {
                return fileURL
            }
        }

        throw MachOToolServiceError.noSupportedBinary(frameworkURL)
    }

    private func inspectionUnits(for fileURL: URL, rootURL: URL) throws -> [InspectionUnit] {
        if let archiveInspection = try archiveInspector.inspect(url: fileURL) {
            let details = try archiveUnits(for: fileURL, inspection: archiveInspection, rootURL: rootURL)
            return details
        }

        let container = try MachOContainer.parse(at: fileURL)
        let architectures = container.slices.map { architectureName(cpuType: $0.header.cpuType, cpuSubtype: $0.header.cpuSubtype) }
        let platforms = Array(Set(container.slices.compactMap { platformIdentifier(for: $0.buildVersion?.platform ?? $0.versionMin?.platform) })).sorted()
        return [
            InspectionUnit(
                label: relativePath(for: fileURL, rootURL: rootURL),
                architectures: Array(Set(architectures)).sorted(),
                platforms: platforms
            )
        ]
    }

    private func archiveUnits(for archiveURL: URL, inspection: ArchiveInspection, rootURL: URL) throws -> [InspectionUnit] {
        let architectures = inspection.architectures.isEmpty ? ["unknown"] : inspection.architectures
        var units = [InspectionUnit]()

        for architecture in architectures {
            let extraction = try archiveInspector.extractThinArchive(
                url: archiveURL,
                preferredArchitecture: inspection.kind == .fatArchive ? architecture : nil
            )
            defer { try? fileManager.removeItem(at: extraction.archiveURL.deletingLastPathComponent()) }

            let membersDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("MachOKnifeContamination-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: membersDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: membersDirectory) }

            let members = try archiveInspector.listMembers(in: extraction.archiveURL)
                .filter { !$0.hasPrefix("__.SYMDEF") && $0 != "/" && $0 != "//" }
            try archiveInspector.extractMembers(from: extraction.archiveURL, to: membersDirectory)

            let prefix = relativePath(for: archiveURL, rootURL: rootURL)
            for memberName in members {
                let memberURL = membersDirectory.appendingPathComponent(memberName)
                guard let container = try? MachOContainer.parse(at: memberURL), let slice = container.slices.first else {
                    units.append(
                        InspectionUnit(
                            label: "\(prefix) [\(architecture)] :: \(memberName)",
                            architectures: [architecture],
                            platforms: []
                        )
                    )
                    continue
                }
                units.append(
                    InspectionUnit(
                        label: "\(prefix) [\(architecture)] :: \(memberName)",
                        architectures: [architectureName(cpuType: slice.header.cpuType, cpuSubtype: slice.header.cpuSubtype)],
                        platforms: [platformIdentifier(for: slice.buildVersion?.platform ?? slice.versionMin?.platform)].compactMap { $0 }
                    )
                )
            }
        }

        return units
    }
}

public final class MachOMergeSplitService {
    private let archiveInspector = ArchiveInspector()
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func availableArchitectures(for url: URL) throws -> [String] {
        if let archiveInspection = try archiveInspector.inspect(url: url) {
            let architectures = archiveInspection.architectures
            guard architectures.isEmpty == false else {
                throw MachOToolServiceError.noArchitectures(url)
            }
            return architectures
        }

        let container = try MachOContainer.parse(at: url)
        let architectures = Array(
            Set(container.slices.map { architectureName(cpuType: $0.header.cpuType, cpuSubtype: $0.header.cpuSubtype) })
        ).sorted(by: architectureSort)
        guard architectures.isEmpty == false else {
            throw MachOToolServiceError.noArchitectures(url)
        }
        return architectures
    }

    public func split(
        inputURL: URL,
        architectures: [String],
        outputDirectoryURL: URL
    ) throws -> [URL] {
        let requestedArchitectures = architectures.isEmpty ? try availableArchitectures(for: inputURL) : architectures
        try fileManager.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let ext = inputURL.pathExtension

        if let archiveInspection = try archiveInspector.inspect(url: inputURL) {
            return try requestedArchitectures.map { architecture in
                let extraction = try archiveInspector.extractThinArchive(
                    url: inputURL,
                    preferredArchitecture: archiveInspection.kind == .fatArchive ? architecture : nil
                )
                defer { try? fileManager.removeItem(at: extraction.archiveURL.deletingLastPathComponent()) }

                let outputURL = outputDirectoryURL.appendingPathComponent(composeOutputName(baseName: baseName, architecture: architecture, pathExtension: ext))
                if fileManager.fileExists(atPath: outputURL.path) {
                    try fileManager.removeItem(at: outputURL)
                }
                try fileManager.copyItem(at: extraction.archiveURL, to: outputURL)
                return outputURL
            }
        }

        return try requestedArchitectures.map { architecture in
            let outputURL = outputDirectoryURL.appendingPathComponent(composeOutputName(baseName: baseName, architecture: architecture, pathExtension: ext))
            if fileManager.fileExists(atPath: outputURL.path) {
                try fileManager.removeItem(at: outputURL)
            }
            try runResolvedTool(named: "lipo", arguments: ["-thin", architecture, inputURL.path, "-output", outputURL.path])
            return outputURL
        }
    }

    public func merge(inputURLs: [URL], outputURL: URL) throws {
        guard inputURLs.count >= 2 else {
            throw MachOToolServiceError.mergeNeedsMultipleInputs
        }

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        try runResolvedTool(
            named: "lipo",
            arguments: ["-create"] + inputURLs.map(\.path) + ["-output", outputURL.path]
        )
    }

    public func suggestedMergedOutputFileName(for inputURLs: [URL]) -> String {
        guard inputURLs.isEmpty == false else {
            return "Merged"
        }

        let cleanedBaseNames = inputURLs.map { sanitizedMergeBaseName(for: $0) }.filter { $0.isEmpty == false }
        let commonPrefix = longestUsefulCommonPrefix(in: cleanedBaseNames)
        let baseName = commonPrefix.isEmpty
            ? (cleanedBaseNames.first ?? "Merged")
            : commonPrefix
        let pathExtension = inputURLs
            .map(\.pathExtension)
            .first { $0.isEmpty == false }

        if let pathExtension, pathExtension.isEmpty == false {
            return "\(baseName).\(pathExtension)"
        }
        return baseName
    }

    private func composeOutputName(baseName: String, architecture: String, pathExtension: String) -> String {
        if pathExtension.isEmpty {
            return "\(baseName)-\(architecture)"
        }
        return "\(baseName)-\(architecture).\(pathExtension)"
    }

    private func sanitizedMergeBaseName(for url: URL) -> String {
        let rawBaseName = url.deletingPathExtension().lastPathComponent
        let parts = rawBaseName
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." || $0 == " " })
            .map(String.init)

        let filteredParts = parts.filter { mergeNameNoiseTokens.contains($0.lowercased()) == false }
        let candidate = filteredParts.joined(separator: "-")
        let trimmed = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "-_ ."))
        return trimmed.isEmpty ? rawBaseName.trimmingCharacters(in: CharacterSet(charactersIn: "-_ .")) : trimmed
    }

    private func longestUsefulCommonPrefix(in names: [String]) -> String {
        guard var prefix = names.first, names.count > 1 else {
            return names.first ?? ""
        }

        for name in names.dropFirst() {
            while name.hasPrefix(prefix) == false, prefix.isEmpty == false {
                prefix.removeLast()
            }
        }

        let separators = CharacterSet(charactersIn: "-_ .")
        while let last = prefix.unicodeScalars.last, separators.contains(last) {
            prefix.removeLast()
        }

        return prefix
    }

    private func mergeSlices(for inputURLs: [URL]) throws -> [MergedContainerSlice] {
        try inputURLs.flatMap { inputURL in
            if let archiveInspection = try archiveInspector.inspect(url: inputURL) {
                let architectures = archiveInspection.architectures
                guard architectures.isEmpty == false else {
                    throw MachOToolServiceError.noArchitectures(inputURL)
                }
                return try architectures.map { architecture in
                    let extraction = try archiveInspector.extractThinArchive(
                        url: inputURL,
                        preferredArchitecture: archiveInspection.kind == .fatArchive ? architecture : nil
                    )
                    defer { try? fileManager.removeItem(at: extraction.archiveURL.deletingLastPathComponent()) }
                    return try MergedContainerSlice(
                        architecture: extraction.architecture,
                        data: Data(contentsOf: extraction.archiveURL, options: [.mappedIfSafe])
                    )
                }
            }

            let container = try MachOContainer.parse(at: inputURL)
            guard container.slices.count == 1 else {
                throw MachOToolServiceError.unsupportedInput(inputURL)
            }

            let slice = container.slices[0]
            return [
                try MergedContainerSlice(
                    cpuType: slice.header.cpuType,
                    cpuSubtype: slice.header.cpuSubtype,
                    architecture: architectureName(cpuType: slice.header.cpuType, cpuSubtype: slice.header.cpuSubtype),
                    data: Data(contentsOf: inputURL, options: [.mappedIfSafe])
                ),
            ]
        }
    }

    private func writeFatContainer(slices: [MergedContainerSlice], to outputURL: URL) throws {
        var data = Data()
        let count = UInt32(slices.count)
        data.append(contentsOf: FAT_MAGIC.bigEndian.bytes)
        data.append(contentsOf: count.bigEndian.bytes)

        let alignment: UInt32 = 14
        let fatArchSize = MemoryLayout<fat_arch>.size
        let headerSize = MemoryLayout<fat_header>.size + fatArchSize * slices.count
        var currentOffset = alignedOffset(headerSize, alignment: Int(alignment))
        var sliceOffsets = [Int]()

        for slice in slices {
            sliceOffsets.append(currentOffset)
            currentOffset = alignedOffset(currentOffset + slice.data.count, alignment: Int(alignment))
        }

        for (index, slice) in slices.enumerated() {
            data.append(contentsOf: UInt32(bitPattern: slice.cpuType).bigEndian.bytes)
            data.append(contentsOf: UInt32(bitPattern: slice.cpuSubtype).bigEndian.bytes)
            data.append(contentsOf: UInt32(sliceOffsets[index]).bigEndian.bytes)
            data.append(contentsOf: UInt32(slice.data.count).bigEndian.bytes)
            data.append(contentsOf: alignment.bigEndian.bytes)
        }

        if data.count < headerSize {
            data.append(Data(repeating: 0, count: headerSize - data.count))
        }

        for (index, slice) in slices.enumerated() {
            if data.count < sliceOffsets[index] {
                data.append(Data(repeating: 0, count: sliceOffsets[index] - data.count))
            }
            data.append(slice.data)
        }

        try data.write(to: outputURL, options: [.atomic])
    }

    private func alignedOffset(_ offset: Int, alignment: Int) -> Int {
        let mask = (1 << alignment) - 1
        return (offset + mask) & ~mask
    }
}

private struct ResolvedBinaryInput {
    let originalURL: URL
    let binaryURL: URL
    let displayName: String
}

private struct ArchiveArchitectureDetail {
    let architecture: String
    let memberCount: Int
    let platforms: [String]
    let minimumOSVersions: [String]
    let sdkVersions: [String]
    let sampleMember: String?
}

private struct ArchiveMemberMetadata {
    let name: String
    let platform: String?
    let minimumOS: String?
    let sdk: String?
}

private struct InspectionUnit {
    let label: String
    let architectures: [String]
    let platforms: [String]
}

private struct MergedContainerSlice {
    let cpuType: Int32
    let cpuSubtype: Int32
    let architecture: String
    let data: Data

    init(architecture: String, data: Data) throws {
        let cpu = try cpuDescription(for: architecture)
        self.cpuType = cpu.cpuType
        self.cpuSubtype = cpu.cpuSubtype
        self.architecture = architecture
        self.data = data
    }

    init(cpuType: Int32, cpuSubtype: Int32, architecture: String, data: Data) {
        self.cpuType = cpuType
        self.cpuSubtype = cpuSubtype
        self.architecture = architecture
        self.data = data
    }
}

private func platformIdentifier(for platform: MachOPlatform?) -> String? {
    guard let platform else { return nil }
    switch platform {
    case .macOS:
        return "macos"
    case .iOS:
        return "iphoneos"
    case .tvOS:
        return "tvos"
    case .watchOS:
        return "watchos"
    case .bridgeOS:
        return "bridgeos"
    case .macCatalyst:
        return "maccatalyst"
    case .iOSSimulator:
        return "iphonesimulator"
    case .tvOSSimulator:
        return "tvossimulator"
    case .watchOSSimulator:
        return "watchsimulator"
    case .driverKit:
        return "driverkit"
    case .visionOS:
        return "xros"
    case .visionOSSimulator:
        return "xrsimulator"
    case .firmware:
        return "firmware"
    case .sepOS:
        return "sepos"
    case .unknown:
        return "unknown"
    }
}

private func normalizedPlatformTarget(_ target: String) -> String {
    switch target.lowercased() {
    case "macosx", "macos":
        return "macos"
    case "ios", "iphoneos":
        return "iphoneos"
    case "simulator", "iossimulator", "iphonesimulator":
        return "iphonesimulator"
    case "maccatalyst", "catalyst":
        return "maccatalyst"
    case "tvos":
        return "tvos"
    case "tvossimulator":
        return "tvossimulator"
    case "watchos":
        return "watchos"
    case "watchsimulator":
        return "watchsimulator"
    case "visionos", "xros":
        return "xros"
    case "xrsimulator":
        return "xrsimulator"
    default:
        return target.lowercased()
    }
}

private func cpuDescription(for architecture: String) throws -> (cpuType: Int32, cpuSubtype: Int32) {
    switch architecture.lowercased() {
    case "arm64":
        return (CPU_TYPE_ARM64, 0)
    case "arm64e":
        return (CPU_TYPE_ARM64, 2)
    case "x86_64":
        return (CPU_TYPE_X86_64, 3)
    case "i386":
        return (CPU_TYPE_X86, 3)
    case "armv7":
        return (CPU_TYPE_ARM, 9)
    case "armv7s":
        return (CPU_TYPE_ARM, 11)
    case "armv7k":
        return (CPU_TYPE_ARM, 12)
    default:
        throw MachOToolServiceError.processFailed("Unsupported architecture for merge: \(architecture)")
    }
}

private func architectureName(cpuType: Int32, cpuSubtype: Int32) -> String {
    let subtype = cpuSubtype & 0x00FF_FFFF

    switch cpuType {
    case CPU_TYPE_ARM64:
        return subtype == 2 ? "arm64e" : "arm64"
    case CPU_TYPE_X86_64:
        return "x86_64"
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

private func cpuTypeDescription(_ value: Int32) -> String {
    switch value {
    case CPU_TYPE_ARM64:
        return "ARM64"
    case CPU_TYPE_X86_64:
        return "X86_64"
    case CPU_TYPE_ARM:
        return "ARM"
    case CPU_TYPE_X86:
        return "X86"
    case CPU_TYPE_POWERPC:
        return "POWERPC"
    case CPU_TYPE_POWERPC64:
        return "POWERPC64"
    default:
        return "Unknown CPU"
    }
}

private func cpuSubtypeDescription(_ value: Int32) -> String {
    let subtype = value & 0x00FF_FFFF
    switch subtype {
    case 0:
        return "All"
    case 2:
        return "arm64e"
    case 6:
        return "armv6"
    case 9:
        return "armv7"
    case 10:
        return "armv7f"
    case 11:
        return "armv7s"
    case 12:
        return "armv7k"
    default:
        return "Subtype \(subtype)"
    }
}

private func fileTypeDescription(_ value: UInt32) -> String {
    switch value {
    case UInt32(MH_OBJECT):
        return "Relocatable Object"
    case UInt32(MH_EXECUTE):
        return "Executable"
    case UInt32(MH_FVMLIB):
        return "Fixed VM Library"
    case UInt32(MH_CORE):
        return "Core"
    case UInt32(MH_PRELOAD):
        return "Preloaded Executable"
    case UInt32(MH_DYLIB):
        return "Dynamic Library"
    case UInt32(MH_DYLINKER):
        return "Dynamic Linker"
    case UInt32(MH_BUNDLE):
        return "Bundle"
    case UInt32(MH_DYLIB_STUB):
        return "Shared Library Stub"
    case UInt32(MH_DSYM):
        return "dSYM Companion"
    case UInt32(MH_KEXT_BUNDLE):
        return "Kext Bundle"
    case UInt32(MH_FILESET):
        return "Fileset"
    default:
        return "Unknown"
    }
}

private func architectureSort(_ lhs: String, _ rhs: String) -> Bool {
    let rank: [String: Int] = [
        "arm64": 0,
        "arm64e": 1,
        "x86_64": 2,
        "i386": 3,
        "armv7": 4,
        "armv7s": 5,
    ]
    return (rank[lhs, default: 99], lhs) < (rank[rhs, default: 99], rhs)
}

private func relativePath(for fileURL: URL, rootURL: URL) -> String {
    let filePath = fileURL.standardizedFileURL.path
    let rootPath = rootURL.standardizedFileURL.path
    if filePath.hasPrefix(rootPath + "/") {
        return String(filePath.dropFirst(rootPath.count + 1))
    }
    return fileURL.lastPathComponent
}

private func runProcess(launchPath: String, arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let output = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile()
                + stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown tool error."
        throw MachOToolServiceError.processFailed(output.isEmpty ? "Tool failed: \(launchPath)" : output)
    }
}

private func runResolvedTool(named tool: String, arguments: [String]) throws {
    let launchPath = try DeveloperToolLocator.path(named: tool)
    try runProcess(launchPath: launchPath, arguments: arguments)
}

private enum DeveloperToolLocator {
    static func path(named tool: String) throws -> String {
        let candidates = candidatePaths(for: tool)
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }
        throw MachOToolServiceError.processFailed("Unable to locate developer tool: \(tool)")
    }

    private static func candidatePaths(for tool: String) -> [String] {
        let developerRoots = preferredDeveloperRoots()
        let toolchainRelativePath = "Toolchains/XcodeDefault.xctoolchain/usr/bin/\(tool)"
        let developerRelativePath = "usr/bin/\(tool)"

        let developerCandidates = developerRoots.flatMap { root in
            [
                root.appending(path: toolchainRelativePath).path,
                root.appending(path: developerRelativePath).path,
            ]
        }

        let systemCandidates = [
            "/usr/bin/\(tool)",
            "/bin/\(tool)",
        ]

        return developerCandidates + systemCandidates
    }

    private static func preferredDeveloperRoots() -> [URL] {
        var roots = [URL]()
        let fileManager = FileManager.default

        if
            let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"],
            developerDir.isEmpty == false
        {
            roots.append(URL(fileURLWithPath: developerDir, isDirectory: true))
        }

        if let selectedRoot = try? selectedDeveloperRoot() {
            roots.append(selectedRoot)
        }

        roots.append(URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer", isDirectory: true))
        roots.append(URL(fileURLWithPath: "/Applications/XCode.app/Contents/Developer", isDirectory: true))

        return roots.reduce(into: [URL]()) { result, root in
            guard fileManager.fileExists(atPath: root.path) else { return }
            if result.contains(root) == false {
                result.append(root)
            }
        }
    }

    private static func selectedDeveloperRoot() throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw MachOToolServiceError.processFailed("Unable to determine active developer directory.")
        }

        let path = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard path.isEmpty == false else {
            throw MachOToolServiceError.processFailed("Unable to determine active developer directory.")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

private let mergeNameNoiseTokens: Set<String> = [
    "arm64",
    "arm64e",
    "x86_64",
    "i386",
    "armv7",
    "armv7s",
    "armv7k",
    "iphoneos",
    "iphonesimulator",
    "iossimulator",
    "ios",
    "macos",
    "macosx",
    "maccatalyst",
    "catalyst",
    "tvos",
    "tvossimulator",
    "watchos",
    "watchsimulator",
    "xros",
    "visionos",
    "simulator",
    "device",
    "debug",
    "release",
    "universal",
    "fat",
]

private extension FixedWidthInteger {
    var bytes: [UInt8] {
        withUnsafeBytes(of: self) { Array($0) }
    }
}

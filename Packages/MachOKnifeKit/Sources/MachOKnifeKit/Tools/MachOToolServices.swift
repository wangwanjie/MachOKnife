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

    /// 机器可读的 JSON 形式（键按字母排序、带缩进），供 CLI 的 `--json` 之类输出或脚本消费。
    ///
    /// 结构为 `{"title": ..., "summary": [...], "sections": [{"title": ..., "lines": [...]}]}`；
    /// 与 `renderedText` 不同，空 section 也会保留，调用方可以据此区分“无结果”和“缺少该部分”。
    public var renderedJSON: String {
        renderJSON(ToolTextReportJSON(report: self))
    }
}

/// `ToolTextReport` 的 JSON 编码模型。
private struct ToolTextReportJSON: Encodable {
    struct Section: Encodable {
        let title: String
        let lines: [String]
    }

    let title: String
    let summary: [String]
    let sections: [Section]

    init(report: ToolTextReport) {
        title = report.title
        summary = report.summaryLines
        sections = report.sections.map { Section(title: $0.title, lines: $0.lines) }
    }
}

/// `BinaryContaminationReport` 的 JSON 编码模型：在报告文本之外附带结构化的计数。
private struct BinaryContaminationReportJSON: Encodable {
    let mode: String
    let target: String
    let okCount: Int
    let mismatchCount: Int
    let uncheckedCount: Int
    let report: ToolTextReportJSON
}

/// 以稳定的格式（排序键、缩进、不转义斜杠）编码 JSON；这些模型只含字符串和整数，编码不会失败。
private func renderJSON<Value: Encodable>(_ value: Value) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value) else {
        return "{}"
    }
    return String(decoding: data, as: UTF8.self)
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

    /// 机器可读的 JSON 形式：包含模式、目标、各类计数以及完整的报告内容。
    public var renderedJSON: String {
        renderJSON(
            BinaryContaminationReportJSON(
                mode: mode.rawValue,
                target: target,
                okCount: okCount,
                mismatchCount: mismatchCount,
                uncheckedCount: uncheckedCount,
                report: ToolTextReportJSON(report: textReport)
            )
        )
    }
}

public enum MachOToolServiceError: LocalizedError {
    case noSupportedBinary(URL)
    case ambiguousPackage(URL, count: Int)
    case unsupportedInput(URL)
    case noArchitectures(URL)
    case architectureNotFound(String, available: [String])
    case mergeNeedsMultipleInputs
    case processFailed(String)
    /// 移除架构后不会剩下任何切片（例如要求移除全部架构）。
    case cannotRemoveAllArchitectures(URL)
    /// 输入不是通用（fat）二进制或 fat 静态库，无法移除其中的架构。
    case notUniversal(URL)

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
        case let .architectureNotFound(architecture, available):
            return "The input does not contain the architecture \(architecture). Available architectures: \(available.joined(separator: ", "))."
        case .mergeNeedsMultipleInputs:
            return "Choose at least two input files to merge."
        case let .processFailed(message):
            return message
        case let .cannotRemoveAllArchitectures(url):
            return "Removing the selected architectures would leave \(url.lastPathComponent) without any architecture."
        case let .notUniversal(url):
            return "\(url.lastPathComponent) is not a universal binary or fat archive."
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
                    "CPU Subtype: \(cpuSubtypeDescription(slice.header.cpuSubtype, cpuType: slice.header.cpuType)) (\(slice.header.cpuSubtype))",
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
            let members = try ArchiveArchitectureMembers.collect(
                architecture: architecture,
                in: archiveURL,
                inspection: inspection,
                archiveInspector: archiveInspector,
                fileManager: fileManager
            )

            let inspectedMembers = members.compactMap { member -> ArchiveMemberMetadata? in
                guard let slice = member.slices?.first else {
                    return nil
                }
                return ArchiveMemberMetadata(
                    name: member.name,
                    platform: platformIdentifier(for: slice.buildVersion?.platform ?? slice.versionMin?.platform),
                    minimumOS: slice.buildVersion?.minimumOS.description ?? slice.versionMin?.minimumOS.description,
                    sdk: slice.buildVersion?.sdk.description ?? slice.versionMin?.sdk.description
                )
            }

            return ArchiveArchitectureDetail(
                architecture: architecture,
                memberCount: members.count,
                platforms: Array(Set(inspectedMembers.compactMap(\.platform))).sorted(),
                minimumOSVersions: numericallySortedVersions(inspectedMembers.compactMap(\.minimumOS)),
                sdkVersions: numericallySortedVersions(inspectedMembers.compactMap(\.sdk)),
                sampleMember: inspectedMembers.first?.name ?? members.first?.name
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

        let prefix = relativePath(for: archiveURL, rootURL: rootURL)

        for architecture in architectures {
            let members = try ArchiveArchitectureMembers.collect(
                architecture: architecture,
                in: archiveURL,
                inspection: inspection,
                archiveInspector: archiveInspector,
                fileManager: fileManager
            )

            for member in members {
                let label = "\(prefix) [\(architecture)] :: \(member.name)"
                guard let slice = member.slices?.first else {
                    units.append(InspectionUnit(label: label, architectures: [architecture], platforms: []))
                    continue
                }
                units.append(
                    InspectionUnit(
                        label: label,
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
            let available = archiveInspection.architectures
            if available.contains("unknown") == false,
               let missing = requestedArchitectures.first(where: { available.contains($0) == false }) {
                throw MachOToolServiceError.architectureNotFound(missing, available: available)
            }
            return try requestedArchitectures.map { architecture in
                let outputURL = outputDirectoryURL.appendingPathComponent(composeOutputName(baseName: baseName, architecture: architecture, pathExtension: ext))
                if ArchiveArchitectureMembers.filtersMembersByArchitecture(archiveInspection) {
                    // 非 fat 但混有多个架构目标文件的静态库：只保留该架构的成员重新打包，
                    // 而不是把整个混合归档原样复制成“某架构”的输出。
                    try writeArchitectureMembers(architecture, of: inputURL, inspection: archiveInspection, to: outputURL)
                } else {
                    let extraction = try archiveInspector.extractThinArchive(
                        url: inputURL,
                        preferredArchitecture: archiveInspection.kind == .fatArchive ? architecture : nil
                    )
                    defer {
                        try? fileManager.removeItem(at: extraction.archiveURL.deletingLastPathComponent())
                    }
                    try writeReplacingOutput(at: outputURL) { temporaryURL in
                        try fileManager.copyItem(at: extraction.archiveURL, to: temporaryURL)
                    }
                }
                return outputURL
            }
        }

        let container = try MachOContainer.parse(at: inputURL)
        let available = container.slices.map { architectureName(cpuType: $0.header.cpuType, cpuSubtype: $0.header.cpuSubtype) }
        if let missing = requestedArchitectures.first(where: { available.contains($0) == false }) {
            throw MachOToolServiceError.architectureNotFound(missing, available: available)
        }

        return try requestedArchitectures.map { architecture in
            let outputURL = outputDirectoryURL.appendingPathComponent(composeOutputName(baseName: baseName, architecture: architecture, pathExtension: ext))
            // 先写临时文件再替换：lipo 失败时不会删掉用户已有的同名输出文件。
            try writeReplacingOutput(at: outputURL) { temporaryURL in
                if container.kind == .fat {
                    try runResolvedTool(named: "lipo", arguments: ["-thin", architecture, inputURL.path, "-output", temporaryURL.path])
                } else {
                    // `lipo -thin` rejects thin inputs; a thin file already is the requested slice.
                    try fileManager.copyItem(at: inputURL, to: temporaryURL)
                }
            }
            return outputURL
        }
    }

    public func merge(inputURLs: [URL], outputURL: URL) throws {
        guard inputURLs.count >= 2 else {
            throw MachOToolServiceError.mergeNeedsMultipleInputs
        }

        // 旧实现会先删除 outputURL 再运行 lipo：当输出路径正好是某个输入文件时会把输入删掉，
        // lipo 失败时也会丢失已有的输出文件。现在 lipo 写入同目录的临时文件，成功后再替换。
        try writeReplacingOutput(at: outputURL) { temporaryURL in
            try runResolvedTool(
                named: "lipo",
                arguments: ["-create"] + inputURLs.map(\.path) + ["-output", temporaryURL.path]
            )
        }
    }

    /// 从通用（fat）Mach-O 或 fat 静态库中移除指定架构，结果写入 `outputURL`（可以与输入相同）。
    ///
    /// 典型用途是在提交 App Store 之前去掉 x86_64 / i386 模拟器切片。
    /// - Throws: 输入不是 fat 容器、请求的架构不存在，或移除后不剩任何架构时抛出 `MachOToolServiceError`。
    public func removeArchitectures(_ architectures: [String], from inputURL: URL, outputURL: URL) throws {
        let isFatArchive = try archiveInspector.inspect(url: inputURL)?.kind == .fatArchive
        let isFatMachO = isFatArchive == false && (try? MachOContainer.parse(at: inputURL))?.kind == .fat
        guard isFatArchive || isFatMachO else {
            throw MachOToolServiceError.notUniversal(inputURL)
        }

        let available = try availableArchitectures(for: inputURL)
        let removed = Set(architectures)
        if let missing = architectures.first(where: { available.contains($0) == false }) {
            throw MachOToolServiceError.architectureNotFound(missing, available: available)
        }
        guard available.contains(where: { removed.contains($0) == false }) else {
            throw MachOToolServiceError.cannotRemoveAllArchitectures(inputURL)
        }

        try writeReplacingOutput(at: outputURL) { temporaryURL in
            if removed.isEmpty {
                // 没有需要移除的架构时直接复制，保持输出语义一致。
                try fileManager.copyItem(at: inputURL, to: temporaryURL)
                return
            }
            // lipo 的 -remove 可以重复出现，每个参数移除一个架构；对 fat 静态库同样适用。
            let removeArguments = removed.sorted(by: architectureSort).flatMap { ["-remove", $0] }
            try runResolvedTool(named: "lipo", arguments: [inputURL.path] + removeArguments + ["-output", temporaryURL.path])
        }
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

    /// 把 `produce` 写出的临时文件安全地放到 `outputURL`。
    ///
    /// 临时文件位于输出目录中（同一卷，替换是原子的）；`produce` 或替换失败时临时文件会被删除，
    /// 已有的输出文件保持不变。输出路径与某个输入相同也是安全的，因为输入在替换前一直存在。
    private func writeReplacingOutput(at outputURL: URL, _ produce: (URL) throws -> Void) throws {
        let temporaryURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".\(outputURL.lastPathComponent).\(UUID().uuidString).tmp")
        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        try produce(temporaryURL)

        if fileManager.fileExists(atPath: outputURL.path) {
            _ = try fileManager.replaceItemAt(outputURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: outputURL)
        }
    }

    /// 把混合架构静态库中属于 `architecture` 的成员重新打包成一个单架构静态库，并生成新的符号表。
    private func writeArchitectureMembers(
        _ architecture: String,
        of archiveURL: URL,
        inspection: ArchiveInspection,
        to outputURL: URL
    ) throws {
        try ArchiveArchitectureMembers.withMembers(
            architecture: architecture,
            in: archiveURL,
            inspection: inspection,
            archiveInspector: archiveInspector,
            fileManager: fileManager
        ) { members in
            guard members.isEmpty == false else {
                throw MachOToolServiceError.architectureNotFound(architecture, available: inspection.architectures)
            }
            try writeReplacingOutput(at: outputURL) { temporaryURL in
                try archiveInspector.writeArchive(
                    outputURL: temporaryURL,
                    members: members.map { ArchiveMemberSource(name: $0.name, fileURL: $0.fileURL) },
                    generateSymbolTable: true
                )
            }
        }
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

private func architectureName(cpuType: Int32, cpuSubtype: Int32) -> String {
    MachOArchitectureNaming.name(cpuType: cpuType, cpuSubtype: cpuSubtype)
}

private func cpuTypeDescription(_ value: Int32) -> String {
    switch value {
    case CPU_TYPE_ARM64:
        return "ARM64"
    case MachOArchitectureNaming.cpuTypeARM64_32:
        return "ARM64_32"
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

private func cpuSubtypeDescription(_ value: Int32, cpuType: Int32) -> String {
    let subtype = value & 0x00FF_FFFF
    if cpuType == CPU_TYPE_ARM64 || cpuType == CPU_TYPE_X86_64 || cpuType == MachOArchitectureNaming.cpuTypeARM64_32 {
        let name = MachOArchitectureNaming.name(cpuType: cpuType, cpuSubtype: value)
        if name == "arm64e" || name == "x86_64h" {
            return name
        }
    }
    switch subtype {
    case 0:
        return "All"
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
    let result = try ToolProcessRunner.run(executableURL: URL(fileURLWithPath: launchPath), arguments: arguments)
    guard result.succeeded else {
        let output = result.combinedOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let result = try ToolProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcode-select"),
            arguments: ["-p"]
        )
        guard result.succeeded else {
            throw MachOToolServiceError.processFailed("Unable to determine active developer directory.")
        }

        let path = String(decoding: result.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

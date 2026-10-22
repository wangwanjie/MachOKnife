import CoreMachO
import Foundation
import MachOKnifeKit

/// 机器可读（JSON）输出。
///
/// 键名与取值是对外约定：脚本会依赖它们，因此新增字段可以，但不要随意改名或改变类型。
/// 缺失的信息统一输出为 JSON `null`，而不是文本输出中的 "unknown"。
enum CLIJSONRenderer {
    static func renderInfo(_ analysis: DocumentAnalysis) throws -> String {
        let slices: [[String: Any]] = analysis.slices.enumerated().map { index, slice in
            [
                "index": index,
                "architecture": MachOArchitectureNaming.name(cpuType: slice.header.cpuType, cpuSubtype: slice.header.cpuSubtype),
                "offset": slice.fileOffset,
                "is64Bit": slice.is64Bit,
                "fileType": CLIReportRenderer.fileTypeLabel(slice.header.fileType),
                "platform": jsonValue(slice.platform.map { CLIReportRenderer.platformLabel($0) }),
                "minimumOS": jsonValue(slice.minimumOS?.description),
                "sdk": jsonValue(slice.sdkVersion?.description),
                "uuid": jsonValue(slice.uuid?.uuidString),
                "loadCommandCount": slice.loadCommandCount,
                "installName": jsonValue(slice.installName),
                "dylibs": slice.dylibReferences.map { dylib in
                    [
                        "path": dylib.path,
                        "kind": CLIReportRenderer.dylibKindLabel(dylib.command),
                    ]
                },
                "rpaths": slice.rpaths,
                "codeSignature": slice.hasCodeSignature,
                "encrypted": (slice.encryptionInfo?.cryptID ?? 0) != 0,
            ]
        }

        return try serialize([
            "file": analysis.fileURL.path,
            "container": CLIReportRenderer.containerLabel(for: analysis.containerKind),
            "slices": slices,
        ])
    }

    static func renderInfo(_ analysis: ArchiveAnalysis) throws -> String {
        let architectures: [[String: Any]] = analysis.architectures.map { architecture in
            [
                "architecture": architecture.architecture,
                "members": architecture.memberCount,
                "parsedMembers": architecture.parsedMemberCount,
                "platforms": architecture.platforms,
                "minimumOSVersions": architecture.minimumOSVersions,
                "sdkVersions": architecture.sdkVersions,
                "installNames": architecture.installNames,
                "dylibs": architecture.dylibReferences,
                "rpaths": architecture.rpaths,
            ]
        }

        return try serialize([
            "file": analysis.fileURL.path,
            "container": CLIReportRenderer.archiveContainerLabel(for: analysis.kind),
            "architectures": architectures,
        ])
    }

    /// `list-dylibs --json`：每个切片的 install name、依赖 dylib 及 LC_RPATH。
    ///
    /// 字段名与 `info --json` 中同名字段保持一致（`installName` / `dylibs` / `rpaths`），便于脚本复用解析逻辑。
    static func renderDylibs(_ analysis: DocumentAnalysis) throws -> String {
        let slices: [[String: Any]] = analysis.slices.enumerated().map { index, slice in
            [
                "index": index,
                "architecture": MachOArchitectureNaming.name(cpuType: slice.header.cpuType, cpuSubtype: slice.header.cpuSubtype),
                "installName": jsonValue(slice.installName),
                "dylibs": slice.dylibReferences.map { dylib in
                    [
                        "path": dylib.path,
                        "kind": CLIReportRenderer.dylibKindLabel(dylib.command),
                    ]
                },
                "rpaths": slice.rpaths,
            ]
        }

        return try serialize([
            "file": analysis.fileURL.path,
            "container": CLIReportRenderer.containerLabel(for: analysis.containerKind),
            "slices": slices,
        ])
    }

    /// 静态库的 `list-dylibs --json`：按架构聚合各成员的 install name、依赖 dylib 及 LC_RPATH。
    static func renderDylibs(_ analysis: ArchiveAnalysis) throws -> String {
        let architectures: [[String: Any]] = analysis.architectures.map { architecture in
            [
                "architecture": architecture.architecture,
                "installNames": architecture.installNames,
                "dylibs": architecture.dylibReferences,
                "rpaths": architecture.rpaths,
            ]
        }

        return try serialize([
            "file": analysis.fileURL.path,
            "container": CLIReportRenderer.archiveContainerLabel(for: analysis.kind),
            "architectures": architectures,
        ])
    }

    /// 可选值转换为 JSON 值：nil 输出为 `null`。
    private static func jsonValue(_ value: String?) -> Any {
        value ?? NSNull()
    }

    /// 键排序 + 缩进，保证输出稳定（便于 diff），并且不转义路径中的 `/`。
    private static func serialize(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}

import CoreMachO
import Foundation

public struct RetagEngine: Sendable {
    private let writer = MachOWriter()

    public init() {}

    public func previewPlatformRetag(
        inputURL: URL,
        platform: MachOPlatform,
        minimumOS: MachOVersion,
        sdk: MachOVersion
    ) throws -> RetagPreview {
        let plan = MachOEditPlan(
            platformEdit: PlatformEdit(platform: platform, minimumOS: minimumOS, sdk: sdk)
        )
        return try RetagPreview(diff: writer.preview(inputURL: inputURL, editPlan: plan))
    }

    public func retagPlatform(
        inputURL: URL,
        outputURL: URL,
        platform: MachOPlatform,
        minimumOS: MachOVersion,
        sdk: MachOVersion
    ) throws -> RetagResult {
        let plan = MachOEditPlan(
            platformEdit: PlatformEdit(platform: platform, minimumOS: minimumOS, sdk: sdk)
        )
        let result = try writer.write(inputURL: inputURL, outputURL: outputURL, editPlan: plan)
        return RetagResult(outputURL: result.outputURL, diff: result.diff)
    }

    public func rewriteDylibPaths(
        inputURL: URL,
        outputURL: URL,
        fromPrefix: String,
        toPrefix: String
    ) throws -> RetagResult {
        let container = try MachOContainer.parse(at: inputURL)
        let dylibEdits: [DylibEdit] = container.slices.flatMap { slice in
            slice.dylibReferences.compactMap { reference in
                guard reference.path.hasPrefix(fromPrefix) else { return nil }
                let suffix = String(reference.path.dropFirst(fromPrefix.count))
                return DylibEdit.replace(oldPath: reference.path, newPath: toPrefix + suffix, command: reference.command)
            }
        }

        let writeResult = try writer.write(
            inputURL: inputURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(dylibEdits: dylibEdits)
        )

        return RetagResult(outputURL: writeResult.outputURL, diff: writeResult.diff)
    }

    public func previewFixDyldCacheDylib(inputURL: URL) throws -> RetagPreview {
        let plan = try makeDyldCacheFixPlan(inputURL: inputURL)
        return try RetagPreview(diff: writer.preview(inputURL: inputURL, editPlan: plan))
    }

    public func fixDyldCacheDylib(inputURL: URL, outputURL: URL) throws -> RetagResult {
        let plan = try makeDyldCacheFixPlan(inputURL: inputURL)
        let result = try writer.write(inputURL: inputURL, outputURL: outputURL, editPlan: plan)
        return RetagResult(outputURL: result.outputURL, diff: result.diff)
    }

    private func makeDyldCacheFixPlan(inputURL: URL) throws -> MachOEditPlan {
        let container = try MachOContainer.parse(at: inputURL)
        guard let slice = container.slices.first else {
            return MachOEditPlan()
        }

        let installName = slice.installName ?? inputURL.path
        let absoluteDirectory = URL(filePath: installName).deletingLastPathComponent().path + "/"
        let rewrittenInstallName = "@rpath/" + URL(filePath: installName).lastPathComponent

        var dylibEdits = [DylibEdit]()
        for reference in slice.dylibReferences where reference.path.hasPrefix(absoluteDirectory) {
            dylibEdits.append(
                .replace(
                    oldPath: reference.path,
                    newPath: "@rpath/" + URL(filePath: reference.path).lastPathComponent,
                    command: reference.command
                )
            )
        }

        var rpathEdits = [RPathEdit]()
        if slice.rpaths.contains("@loader_path") == false {
            rpathEdits.append(.add("@loader_path"))
        }

        return MachOEditPlan(
            installName: rewrittenInstallName,
            dylibEdits: dylibEdits,
            rpathEdits: rpathEdits
        )
    }
}

import Combine
import CoreMachO
import Foundation
import MachOKnifeKit

@MainActor
final class WorkspaceViewModel {
    enum Selection: Hashable {
        case document
        case slice(Int)
    }

    struct OutlineItem: Hashable {
        let title: String
        let selection: Selection?
        let children: [OutlineItem]
    }

    @Published private(set) var currentFileURL: URL?
    @Published private(set) var analysis: DocumentAnalysis?
    @Published private(set) var outlineItems: [OutlineItem] = []
    @Published private(set) var selection: Selection?
    @Published private(set) var editableSlice: EditableSliceViewModel?
    @Published private(set) var selectedSliceSummary: SliceSummary?
    @Published private(set) var detailText = ""
    @Published private(set) var inspectorText = ""
    @Published private(set) var previewText = ""
    @Published private(set) var errorMessage: String?

    private let analysisService = DocumentAnalysisService()
    private let editingService = DocumentEditingService()
    private var editableSlicesByIndex: [Int: EditableSliceViewModel] = [:]

    var hasPendingEdits: Bool {
        do {
            return try makeEditPlan().map(hasChanges(in:)) ?? false
        } catch {
            return false
        }
    }

    var hasLoadedDocument: Bool {
        analysis != nil
    }

    @discardableResult
    func openDocument(at url: URL) -> Bool {
        openDocument(at: url, preservingDrafts: false, preferredSelection: nil)
    }

    func reanalyzeCurrentDocument() {
        guard let currentFileURL else { return }
        _ = openDocument(at: currentFileURL, preservingDrafts: true, preferredSelection: selection)
    }

    func select(_ selection: Selection?) {
        self.selection = selection
        refreshEditableSlice()
        updateDetailOutputs()
    }

    func setInstallNameDraft(_ installName: String) {
        guard var editableSlice else { return }
        editableSlice.installName = installName
        applyDraft(editableSlice)
    }

    func setDylibPathDraft(at index: Int, newPath: String) {
        guard var editableSlice else { return }
        guard editableSlice.dylibReferences.indices.contains(index) else { return }
        editableSlice.dylibReferences[index].path = newPath
        applyDraft(editableSlice)
    }

    func replaceRPath(oldPath: String, newPath: String) {
        guard var editableSlice else { return }
        guard let index = editableSlice.rpaths.firstIndex(of: oldPath) else { return }
        editableSlice.rpaths[index] = newPath
        applyDraft(editableSlice)
    }

    func addRPathDraft(_ path: String) {
        guard var editableSlice else { return }
        editableSlice.rpaths.append(path)
        applyDraft(editableSlice)
    }

    func updateRPathDraft(at index: Int, path: String) {
        guard var editableSlice else { return }
        guard editableSlice.rpaths.indices.contains(index) else { return }
        editableSlice.rpaths[index] = path
        applyDraft(editableSlice)
    }

    func removeRPathDraft(at index: Int) {
        guard var editableSlice else { return }
        guard editableSlice.rpaths.indices.contains(index) else { return }
        editableSlice.rpaths.remove(at: index)
        applyDraft(editableSlice)
    }

    func setPlatformDraft(platform: MachOPlatform, minimumOS: MachOVersion, sdk: MachOVersion) {
        guard var editableSlice else { return }

        let originalPlatform = editableSlice.platformMetadata?.originalPlatform ?? selectedSliceSummary?.platform
        let originalMinimumOS = editableSlice.platformMetadata?.originalMinimumOS ?? selectedSliceSummary?.minimumOS
        let originalSDK = editableSlice.platformMetadata?.originalSDK ?? selectedSliceSummary?.sdkVersion

        editableSlice.platformMetadata = EditablePlatformMetadata(
            originalPlatform: originalPlatform,
            originalMinimumOS: originalMinimumOS,
            originalSDK: originalSDK,
            platform: platform,
            minimumOS: minimumOS,
            sdk: sdk
        )
        applyDraft(editableSlice)
    }

    func previewEdits() throws {
        guard let currentFileURL else { throw WorkspaceEditingError.noDocumentLoaded }
        guard let editPlan = try makeEditPlan() else {
            previewText = ""
            return
        }

        let preview = try editingService.preview(inputURL: currentFileURL, editPlan: editPlan)
        previewText = render(diff: preview.diff)
    }

    func saveEdits(outputURL: URL? = nil, createBackup: Bool = true) throws -> DocumentSaveResult {
        guard let currentFileURL else { throw WorkspaceEditingError.noDocumentLoaded }
        guard let editPlan = try makeEditPlan() else {
            throw WorkspaceEditingError.noPendingEdits
        }

        let savedSliceSelection = selection
        let result = try editingService.save(
            inputURL: currentFileURL,
            outputURL: outputURL,
            editPlan: editPlan,
            createBackup: createBackup
        )

        _ = openDocument(at: result.outputURL, preservingDrafts: false, preferredSelection: savedSliceSelection)
        previewText = render(diff: result.diff)
        return result
    }

    private func openDocument(at url: URL, preservingDrafts: Bool, preferredSelection: Selection?) -> Bool {
        let previousAnalysis = analysis
        let previousDraftsByIndex = editableSlicesByIndex

        do {
            let analysis = try analysisService.analyze(url: url)
            currentFileURL = url
            self.analysis = analysis
            errorMessage = nil
            outlineItems = makeOutlineItems(for: analysis, fileURL: url)
            editableSlicesByIndex = makeEditableSlices(for: analysis)

            if preservingDrafts, let previousAnalysis {
                mergeDrafts(from: previousDraftsByIndex, previousAnalysis: previousAnalysis, newAnalysis: analysis)
            }

            let fallbackSelection: Selection? = analysis.slices.isEmpty ? .document : .slice(0)
            let restoredSelection = validatedSelection(preferredSelection ?? fallbackSelection, in: analysis)
            select(restoredSelection)
            return true
        } catch {
            currentFileURL = url
            analysis = nil
            outlineItems = []
            selection = nil
            detailText = ""
            inspectorText = ""
            previewText = ""
            editableSlice = nil
            selectedSliceSummary = nil
            editableSlicesByIndex = [:]
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func updateDetailOutputs() {
        guard let analysis, let currentFileURL else {
            detailText = ""
            inspectorText = ""
            return
        }

        switch selection ?? .document {
        case .document:
            detailText = """
            File: \(currentFileURL.path)
            Container: \(String(describing: analysis.containerKind))
            Slice Count: \(analysis.slices.count)
            """

            inspectorText = analysis.slices.enumerated().map { index, slice in
                """
                Slice \(index)
                Install Name: \(slice.installName ?? "(none)")
                Dylibs: \(slice.dylibReferences.count)
                RPaths: \(slice.rpaths.count)
                """
            }.joined(separator: "\n\n")
        case let .slice(index):
            guard analysis.slices.indices.contains(index) else {
                detailText = ""
                inspectorText = ""
                return
            }

            let slice = analysis.slices[index]
            detailText = """
            File Offset: \(slice.fileOffset)
            64-bit: \(slice.is64Bit ? "yes" : "no")
            Load Commands: \(slice.loadCommandCount)
            Install Name: \(slice.installName ?? "(none)")
            """

            let dylibLines = slice.dylibReferences.map { reference in
                "DYLIB \(reference.path)"
            }
            let rpathLines = slice.rpaths.map { rpath in
                "RPATH \(rpath)"
            }

            inspectorText = (dylibLines + rpathLines).joined(separator: "\n")
        }
    }

    private func refreshEditableSlice() {
        guard let analysis else {
            editableSlice = nil
            selectedSliceSummary = nil
            previewText = ""
            return
        }

        guard case let .slice(index)? = selection else {
            editableSlice = nil
            selectedSliceSummary = nil
            previewText = ""
            return
        }

        guard analysis.slices.indices.contains(index), let draft = editableSlicesByIndex[index] else {
            editableSlice = nil
            selectedSliceSummary = nil
            previewText = ""
            return
        }

        selectedSliceSummary = analysis.slices[index]
        editableSlice = draft
        previewText = ""
    }

    private func makeEditableSlices(for analysis: DocumentAnalysis) -> [Int: EditableSliceViewModel] {
        Dictionary(uniqueKeysWithValues: analysis.slices.enumerated().map { index, slice in
            (
                index,
                EditableSliceViewModel(
                    sliceIndex: index,
                    installName: slice.installName ?? "",
                    dylibReferences: slice.dylibReferences.enumerated().map { dylibIndex, reference in
                        EditableDylibReference(index: dylibIndex, command: reference.command, path: reference.path)
                    },
                    rpaths: slice.rpaths,
                    platformMetadata: makePlatformMetadata(for: slice)
                )
            )
        })
    }

    private func mergeDrafts(
        from previousDraftsByIndex: [Int: EditableSliceViewModel],
        previousAnalysis: DocumentAnalysis,
        newAnalysis: DocumentAnalysis
    ) {
        let previousDraftsByOffset = Dictionary(
            uniqueKeysWithValues: previousAnalysis.slices.enumerated().compactMap { index, slice in
                previousDraftsByIndex[index].map { (slice.fileOffset, $0) }
            }
        )

        for (index, slice) in newAnalysis.slices.enumerated() {
            guard let existingDraft = previousDraftsByOffset[slice.fileOffset] else { continue }
            editableSlicesByIndex[index] = rebase(existingDraft: existingDraft, onto: slice, newIndex: index)
        }
    }

    private func rebase(existingDraft: EditableSliceViewModel, onto slice: SliceSummary, newIndex: Int) -> EditableSliceViewModel {
        let defaultDraft = EditableSliceViewModel(
            sliceIndex: newIndex,
            installName: existingDraft.installName,
            dylibReferences: slice.dylibReferences.enumerated().map { dylibIndex, reference in
                let draftPath = existingDraft.dylibReferences.first(where: { $0.index == dylibIndex })?.path ?? reference.path
                return EditableDylibReference(index: dylibIndex, command: reference.command, path: draftPath)
            },
            rpaths: existingDraft.rpaths,
            platformMetadata: existingDraft.platformMetadata ?? makePlatformMetadata(for: slice)
        )

        return defaultDraft
    }

    private func makePlatformMetadata(for slice: SliceSummary) -> EditablePlatformMetadata? {
        guard
            let platform = slice.platform,
            let minimumOS = slice.minimumOS,
            let sdkVersion = slice.sdkVersion
        else {
            return nil
        }

        return EditablePlatformMetadata(
            originalPlatform: platform,
            originalMinimumOS: minimumOS,
            originalSDK: sdkVersion,
            platform: platform,
            minimumOS: minimumOS,
            sdk: sdkVersion
        )
    }

    private func validatedSelection(_ selection: Selection?, in analysis: DocumentAnalysis) -> Selection? {
        switch selection {
        case .document:
            return .document
        case let .slice(index):
            return analysis.slices.indices.contains(index) ? .slice(index) : (analysis.slices.isEmpty ? .document : .slice(0))
        case nil:
            return analysis.slices.isEmpty ? .document : .slice(0)
        }
    }

    private func makeOutlineItems(for analysis: DocumentAnalysis, fileURL: URL) -> [OutlineItem] {
        let sliceItems = analysis.slices.enumerated().map { index, slice in
            OutlineItem(
                title: "Slice \(index) • \(slice.is64Bit ? "64-bit" : "32-bit") • \(slice.loadCommandCount) cmds",
                selection: .slice(index),
                children: []
            )
        }

        return [
            OutlineItem(
                title: fileURL.lastPathComponent,
                selection: .document,
                children: sliceItems
            ),
        ]
    }

    private func makeEditPlan() throws -> MachOEditPlan? {
        guard let analysis else { return nil }
        guard case let .slice(selectedIndex)? = selection else { return nil }
        guard let editableSlice = editableSlicesByIndex[selectedIndex] else { return nil }
        guard analysis.slices.indices.contains(selectedIndex) else {
            throw WorkspaceEditingError.invalidSelection
        }

        let originalSlice = analysis.slices[selectedIndex]
        var installName: String?
        if editableSlice.installName != (originalSlice.installName ?? "") {
            installName = editableSlice.installName
        }

        var dylibEdits = [DylibEdit]()
        for draftReference in editableSlice.dylibReferences {
            guard originalSlice.dylibReferences.indices.contains(draftReference.index) else { continue }
            let originalReference = originalSlice.dylibReferences[draftReference.index]
            guard draftReference.path != originalReference.path else { continue }

            dylibEdits.append(
                .replace(
                    oldPath: originalReference.path,
                    newPath: draftReference.path,
                    command: draftReference.command
                )
            )
        }

        let originalRPaths = Set(originalSlice.rpaths)
        let updatedRPaths = Set(editableSlice.rpaths.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        let removedRPaths = originalRPaths.subtracting(updatedRPaths).sorted()
        let addedRPaths = updatedRPaths.subtracting(originalRPaths).sorted()
        let rpathEdits = removedRPaths.map(RPathEdit.remove) + addedRPaths.map(RPathEdit.add)

        let platformEdit: PlatformEdit?
        if let platformMetadata = editableSlice.platformMetadata, platformMetadata.hasChanges {
            platformEdit = PlatformEdit(
                platform: platformMetadata.platform,
                minimumOS: platformMetadata.minimumOS,
                sdk: platformMetadata.sdk
            )
        } else {
            platformEdit = nil
        }

        let editPlan = MachOEditPlan(
            targetSliceOffset: originalSlice.fileOffset,
            installName: installName,
            dylibEdits: dylibEdits,
            rpathEdits: rpathEdits,
            platformEdit: platformEdit
        )

        return hasChanges(in: editPlan) ? editPlan : nil
    }

    private func hasChanges(in editPlan: MachOEditPlan) -> Bool {
        editPlan.installName != nil ||
        !editPlan.dylibEdits.isEmpty ||
        !editPlan.rpathEdits.isEmpty ||
        editPlan.platformEdit != nil ||
        !editPlan.segmentProtectionEdits.isEmpty ||
        editPlan.stripCodeSignature
    }

    private func render(diff: MachODiff) -> String {
        guard !diff.entries.isEmpty else { return "" }

        return diff.entries.map { entry in
            let kind: String
            switch entry.kind {
            case .installName:
                kind = "Install Name"
            case .dylib:
                kind = "Dylib"
            case .rpath:
                kind = "RPath"
            case .platform:
                kind = "Platform"
            case .segmentProtection:
                kind = "Segment Protection"
            case .codeSignature:
                kind = "Code Signature"
            }

            return "\(kind): \(entry.originalValue ?? "(none)") -> \(entry.updatedValue ?? "(removed)")"
        }.joined(separator: "\n")
    }

    private func applyDraft(_ draft: EditableSliceViewModel) {
        editableSlicesByIndex[draft.sliceIndex] = draft
        if case let .slice(selectedIndex)? = selection, selectedIndex == draft.sliceIndex {
            editableSlice = draft
        }
        previewText = ""
    }
}

private enum WorkspaceEditingError: Error {
    case noDocumentLoaded
    case invalidSelection
    case noPendingEdits
}

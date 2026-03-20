import Combine
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
    @Published private(set) var detailText = ""
    @Published private(set) var inspectorText = ""
    @Published private(set) var errorMessage: String?

    private let analysisService = DocumentAnalysisService()

    var hasLoadedDocument: Bool {
        analysis != nil
    }

    func openDocument(at url: URL) {
        do {
            let analysis = try analysisService.analyze(url: url)
            currentFileURL = url
            self.analysis = analysis
            errorMessage = nil
            outlineItems = makeOutlineItems(for: analysis, fileURL: url)
            select(.slice(0))
        } catch {
            currentFileURL = url
            analysis = nil
            outlineItems = []
            selection = nil
            detailText = ""
            inspectorText = ""
            errorMessage = error.localizedDescription
        }
    }

    func reanalyzeCurrentDocument() {
        guard let currentFileURL else { return }
        openDocument(at: currentFileURL)
    }

    func select(_ selection: Selection?) {
        self.selection = selection
        updateDetailOutputs()
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
}

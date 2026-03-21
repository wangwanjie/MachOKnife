import Combine
import CoreMachO
import Foundation
import MachOKnifeKit

@MainActor
final class WorkspaceViewModel {
    enum BrowserAddressMode: String {
        case raw
        case rva
    }

    private enum BrowserHexLayout {
        static let bytesPerLine = 16
        static let linesPerPage = 256
        static let pageSize = bytesPerLine * linesPerPage
    }

    enum Selection: Hashable {
        case document
        case slice(Int)
        case header(Int)
        case loadCommands(Int)
        case loadCommand(sliceIndex: Int, commandIndex: Int)
        case segments(Int)
        case segment(sliceIndex: Int, segmentIndex: Int)
        case section(sliceIndex: Int, segmentIndex: Int, sectionIndex: Int)
        case dylibs(Int)
        case dylib(sliceIndex: Int, dylibIndex: Int)
        case rpaths(Int)
        case rpath(sliceIndex: Int, rpathIndex: Int)
        case symbols(Int)
        case symbol(sliceIndex: Int, symbolIndex: Int)
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
    @Published private(set) var browserDocument: BrowserDocument?
    @Published private(set) var browserOutlineRootNodes: [BrowserNode] = []
    @Published private(set) var browserSelectedNodeID: String?
    @Published private(set) var browserSelectedNode: BrowserNode?
    @Published private(set) var browserAddressMode: BrowserAddressMode = .raw
    @Published private(set) var browserDetailText = ""
    @Published private(set) var browserHexText = ""
    @Published private(set) var browserHexRows: [BrowserHexRow] = []
    @Published private(set) var browserHexPageLabel = ""

    private let analysisService = DocumentAnalysisService()
    private let browserDocumentService = BrowserDocumentService()
    private let editingService = DocumentEditingService()
    private var editableSlicesByIndex: [Int: EditableSliceViewModel] = [:]
    private var browserHexPageIndex = 0

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

    func reloadPresentation() {
        guard let analysis, let currentFileURL else { return }
        outlineItems = makeOutlineItems(for: analysis, fileURL: currentFileURL)
        updateDetailOutputs()
        updateBrowserPresentation()
    }

    func closeCurrentDocument() {
        resetWorkspaceState(currentFileURL: nil, errorMessage: nil)
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

        let savedSelection = selection
        let result = try editingService.save(
            inputURL: currentFileURL,
            outputURL: outputURL,
            editPlan: editPlan,
            createBackup: createBackup
        )

        _ = openDocument(at: result.outputURL, preservingDrafts: false, preferredSelection: savedSelection)
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
            browserDocument = try? browserDocumentService.load(url: url)
            browserOutlineRootNodes = browserDocument?.rootNodes ?? []
            errorMessage = nil
            outlineItems = makeOutlineItems(for: analysis, fileURL: url)
            editableSlicesByIndex = makeEditableSlices(for: analysis)
            browserHexPageIndex = 0

            if preservingDrafts, let previousAnalysis {
                mergeDrafts(from: previousDraftsByIndex, previousAnalysis: previousAnalysis, newAnalysis: analysis)
            }

            let fallbackSelection: Selection? = analysis.slices.isEmpty ? .document : .slice(0)
            let restoredSelection = validatedSelection(preferredSelection ?? fallbackSelection, in: analysis)
            select(restoredSelection)
            selectBrowserNode(browserDocument?.rootNodes.first)
            return true
        } catch {
            resetWorkspaceState(currentFileURL: url, errorMessage: error.localizedDescription)
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
            \(L10n.viewerFileLabel): \(currentFileURL.path)
            \(L10n.viewerContainerLabel): \(String(describing: analysis.containerKind))
            \(L10n.viewerSliceCountLabel): \(analysis.slices.count)
            """

            inspectorText = analysis.slices.enumerated().map { index, slice in
                """
                \(L10n.viewerSliceTitle(index))
                \(L10n.viewerCPUTypeLabel): \(slice.header.cpuType)
                \(L10n.viewerFileTypeLabel): \(formatHex(slice.header.fileType))
                \(L10n.viewerLoadCommandCountLabel): \(slice.loadCommandCount)
                \(L10n.viewerSegmentCountLabel): \(slice.segments.count)
                \(L10n.viewerSymbolCountLabel): \(slice.symbols.count)
                """
            }.joined(separator: "\n\n")

        case let .slice(index):
            guard let slice = slice(at: index, in: analysis) else {
                resetDetailOutputs()
                return
            }

            detailText = """
            \(L10n.viewerSliceTitle(index))
            \(L10n.viewerFileOffsetLabel): \(slice.fileOffset)
            \(L10n.viewerBitnessLabel): \(slice.is64Bit ? L10n.viewerYes : L10n.viewerNo)
            \(L10n.viewerCPUTypeLabel): \(slice.header.cpuType)
            \(L10n.viewerFileTypeLabel): \(formatHex(slice.header.fileType))
            \(L10n.viewerLoadCommandCountLabel): \(slice.loadCommandCount)
            \(L10n.viewerSegmentCountLabel): \(slice.segments.count)
            \(L10n.viewerSymbolCountLabel): \(slice.symbols.count)
            \(L10n.viewerInstallNameLabel): \(slice.installName ?? L10n.viewerNone)
            \(L10n.viewerUUIDLabel): \(slice.uuid?.uuidString ?? L10n.viewerNone)
            """

            inspectorText = """
            \(L10n.viewerPlatformLabel): \(formatPlatform(slice.platform))
            \(L10n.viewerMinimumOSLabel): \(slice.minimumOS?.description ?? L10n.viewerNA)
            \(L10n.viewerSDKLabel): \(slice.sdkVersion?.description ?? L10n.viewerNA)
            \(L10n.viewerCodeSignatureLabel): \(slice.hasCodeSignature ? L10n.viewerPresent : L10n.viewerMissing)
            \(L10n.viewerEncryptionLabel): \(slice.encryptionInfo.map { "cryptID=\($0.cryptID) size=\($0.cryptSize)" } ?? L10n.viewerNone)
            """

        case let .header(index):
            guard let slice = slice(at: index, in: analysis) else {
                resetDetailOutputs()
                return
            }

            detailText = """
            \(L10n.viewerHeaderSection)
            \(L10n.viewerCPUTypeLabel): \(slice.header.cpuType)
            \(L10n.viewerCPUSubtypeLabel): \(slice.header.cpuSubtype)
            \(L10n.viewerFileTypeLabel): \(formatHex(slice.header.fileType))
            \(L10n.viewerNumberOfCommandsLabel): \(slice.header.numberOfCommands)
            \(L10n.viewerSizeOfCommandsLabel): \(slice.header.sizeofCommands)
            \(L10n.viewerFlagsLabel): \(formatHex(slice.header.flags))
            \(L10n.viewerReservedLabel): \(slice.header.reserved.map(formatHex) ?? L10n.viewerNA)
            """

            inspectorText = """
            \(L10n.viewerUUIDLabel): \(slice.uuid?.uuidString ?? L10n.viewerNone)
            \(L10n.viewerCodeSignatureLabel): \(slice.hasCodeSignature ? L10n.viewerPresent : L10n.viewerMissing)
            \(L10n.viewerEncryptionLabel): \(slice.encryptionInfo.map { "cryptID=\($0.cryptID)" } ?? L10n.viewerNone)
            """

        case let .loadCommands(index):
            guard let slice = slice(at: index, in: analysis) else {
                resetDetailOutputs()
                return
            }

            detailText = """
            \(L10n.viewerLoadCommandsSection)
            \(L10n.viewerCountLabel): \(slice.loadCommandCount)
            \(L10n.viewerSizeLabel): \(slice.header.sizeofCommands) bytes
            """

            inspectorText = slice.loadCommands.enumerated().map { commandIndex, command in
                "\(commandIndex). \(commandName(for: command.command))  size=\(command.size)  offset=\(formatHex(UInt64(command.offset)))"
            }.joined(separator: "\n")

        case let .loadCommand(sliceIndex, commandIndex):
            guard
                let slice = slice(at: sliceIndex, in: analysis),
                slice.loadCommands.indices.contains(commandIndex)
            else {
                resetDetailOutputs()
                return
            }

            let command = slice.loadCommands[commandIndex]
            detailText = """
            \(commandName(for: command.command))
            \(L10n.viewerOffsetLabel): \(formatHex(UInt64(command.offset)))
            \(L10n.viewerSizeLabel): \(command.size)
            """
            inspectorText = command.details.isEmpty
                ? L10n.viewerNoDecodedPayload
                : command.details.map { "\($0.key): \($0.value)" }.joined(separator: "\n")

        case let .segments(index):
            guard let slice = slice(at: index, in: analysis) else {
                resetDetailOutputs()
                return
            }

            detailText = """
            \(L10n.viewerSegmentsSection)
            \(L10n.viewerCountLabel): \(slice.segments.count)
            """
            inspectorText = slice.segments.enumerated().map { segmentIndex, segment in
                "\(segmentIndex). \(segment.name)  vm=\(formatHex(segment.vmAddress))  file=\(formatHex(segment.fileOffset))  sections=\(segment.sections.count)"
            }.joined(separator: "\n")

        case let .segment(sliceIndex, segmentIndex):
            guard
                let slice = slice(at: sliceIndex, in: analysis),
                slice.segments.indices.contains(segmentIndex)
            else {
                resetDetailOutputs()
                return
            }

            let segment = slice.segments[segmentIndex]
            detailText = """
            \(L10n.viewerSegmentTitle(segment.name))
            \(L10n.viewerVMAddressLabel): \(formatHex(segment.vmAddress))
            \(L10n.viewerVMSizeLabel): \(formatHex(segment.vmSize))
            \(L10n.viewerFileOffsetLabel): \(formatHex(segment.fileOffset))
            \(L10n.viewerFileSizeLabel): \(formatHex(segment.fileSize))
            \(L10n.viewerMaxProtectionLabel): \(formatProtection(segment.maxProtection))
            \(L10n.viewerInitialProtectionLabel): \(formatProtection(segment.initialProtection))
            \(L10n.viewerFlagsLabel): \(formatHex(segment.flags))
            """
            inspectorText = segment.sections.isEmpty
                ? L10n.viewerNoSections
                : segment.sections.enumerated().map { sectionIndex, section in
                    "\(sectionIndex). \(section.segmentName).\(section.name)  addr=\(formatHex(section.address))  size=\(formatHex(section.size))"
                }.joined(separator: "\n")

        case let .section(sliceIndex, segmentIndex, sectionIndex):
            guard
                let slice = slice(at: sliceIndex, in: analysis),
                slice.segments.indices.contains(segmentIndex),
                slice.segments[segmentIndex].sections.indices.contains(sectionIndex)
            else {
                resetDetailOutputs()
                return
            }

            let section = slice.segments[segmentIndex].sections[sectionIndex]
            detailText = """
            \(L10n.viewerSectionTitle("\(section.segmentName).\(section.name)"))
            \(L10n.viewerAddressLabel): \(formatHex(section.address))
            \(L10n.viewerSizeLabel): \(formatHex(section.size))
            \(L10n.viewerFileOffsetLabel): \(formatHex(UInt64(section.fileOffset)))
            \(L10n.viewerAlignmentLabel): \(section.alignment)
            \(L10n.viewerRelocationOffsetLabel): \(formatHex(UInt64(section.relocationOffset)))
            \(L10n.viewerRelocationCountLabel): \(section.relocationCount)
            \(L10n.viewerFlagsLabel): \(formatHex(section.flags))
            """
            inspectorText = "\(L10n.viewerSegmentsSection): \(section.segmentName)"

        case let .dylibs(index):
            guard let slice = slice(at: index, in: analysis) else {
                resetDetailOutputs()
                return
            }

            detailText = """
            \(L10n.viewerDylibsSection)
            \(L10n.viewerCountLabel): \(slice.dylibReferences.count)
            """
            inspectorText = slice.dylibReferences.enumerated().map { dylibIndex, dylib in
                "\(dylibIndex). \(commandName(for: dylib.command))  \(dylib.path)"
            }.joined(separator: "\n")

        case let .dylib(sliceIndex, dylibIndex):
            guard
                let slice = slice(at: sliceIndex, in: analysis),
                slice.dylibReferences.indices.contains(dylibIndex)
            else {
                resetDetailOutputs()
                return
            }

            let dylib = slice.dylibReferences[dylibIndex]
            detailText = """
            \(L10n.viewerDylibTitle)
            \(L10n.viewerCommandLabel): \(commandName(for: dylib.command))
            \(L10n.viewerPathLabel): \(dylib.path)
            """
            inspectorText = L10n.viewerDylibPathEditableHint

        case let .rpaths(index):
            guard let slice = slice(at: index, in: analysis) else {
                resetDetailOutputs()
                return
            }

            detailText = """
            \(L10n.viewerRPathsSection)
            \(L10n.viewerCountLabel): \(slice.rpaths.count)
            """
            inspectorText = slice.rpaths.enumerated().map { "\($0.offset). \($0.element)" }.joined(separator: "\n")

        case let .rpath(sliceIndex, rpathIndex):
            guard
                let slice = slice(at: sliceIndex, in: analysis),
                slice.rpaths.indices.contains(rpathIndex)
            else {
                resetDetailOutputs()
                return
            }

            detailText = """
            \(L10n.viewerRPathTitle)
            \(L10n.viewerValueLabel): \(slice.rpaths[rpathIndex])
            """
            inspectorText = L10n.viewerRPathEditableHint

        case let .symbols(index):
            guard let slice = slice(at: index, in: analysis) else {
                resetDetailOutputs()
                return
            }

            detailText = """
            \(L10n.viewerSymbolsSection)
            \(L10n.viewerCountLabel): \(slice.symbols.count)
            """
            inspectorText = slice.symbols.prefix(200).enumerated().map { symbolIndex, symbol in
                "\(symbolIndex). \(symbol.name.isEmpty ? L10n.viewerAnonymous : symbol.name)  value=\(formatHex(symbol.value))"
            }.joined(separator: "\n")

        case let .symbol(sliceIndex, symbolIndex):
            guard
                let slice = slice(at: sliceIndex, in: analysis),
                slice.symbols.indices.contains(symbolIndex)
            else {
                resetDetailOutputs()
                return
            }

            let symbol = slice.symbols[symbolIndex]
            detailText = """
            \(L10n.viewerSymbolTitle)
            \(L10n.viewerNameLabel): \(symbol.name.isEmpty ? L10n.viewerAnonymous : symbol.name)
            \(L10n.viewerTypeLabel): \(formatHex(UInt64(symbol.type)))
            \(L10n.viewerSectionLabel): \(symbol.sectionNumber)
            \(L10n.viewerDescriptionLabel): \(formatHex(UInt64(symbol.description)))
            \(L10n.viewerValueLabel): \(formatHex(symbol.value))
            """
            inspectorText = ""
        }
    }

    private func resetDetailOutputs() {
        detailText = ""
        inspectorText = ""
    }

    private func resetWorkspaceState(currentFileURL: URL?, errorMessage: String?) {
        self.currentFileURL = currentFileURL
        analysis = nil
        outlineItems = []
        selection = nil
        detailText = ""
        inspectorText = ""
        previewText = ""
        editableSlice = nil
        selectedSliceSummary = nil
        editableSlicesByIndex = [:]
        self.errorMessage = errorMessage
        resetBrowserState()
    }

    func selectBrowserNode(_ node: BrowserNode?) {
        browserSelectedNodeID = node?.id
        browserSelectedNode = node
        browserHexPageIndex = 0
        updateBrowserPresentation()
    }

    func selectBrowserNode(_ nodeID: String?) {
        browserSelectedNodeID = nodeID
        if browserSelectedNode?.id != nodeID {
            browserSelectedNode = nil
        }
        browserHexPageIndex = 0
        updateBrowserPresentation()
    }

    func setBrowserAddressMode(_ mode: BrowserAddressMode) {
        guard browserAddressMode != mode else { return }
        browserAddressMode = mode
        updateBrowserPresentation()
    }

    func previousBrowserHexPage() {
        guard browserHexPageIndex > 0 else { return }
        browserHexPageIndex -= 1
        updateBrowserHexText()
    }

    func nextBrowserHexPage() {
        guard browserHexPageIndex + 1 < browserHexPageCount() else { return }
        browserHexPageIndex += 1
        updateBrowserHexText()
    }

    var canShowPreviousBrowserHexPage: Bool {
        browserHexPageIndex > 0
    }

    var canShowNextBrowserHexPage: Bool {
        browserHexPageIndex + 1 < browserHexPageCount()
    }

    private func resetBrowserState() {
        browserDocument = nil
        browserOutlineRootNodes = []
        browserSelectedNodeID = nil
        browserSelectedNode = nil
        browserAddressMode = .raw
        browserDetailText = ""
        browserHexText = ""
        browserHexRows = []
        browserHexPageLabel = ""
        browserHexPageIndex = 0
    }

    private func updateBrowserPresentation() {
        updateBrowserDetailText()
        updateBrowserHexText()
    }

    private func updateBrowserDetailText() {
        guard let browserDocument else {
            browserSelectedNode = nil
            browserDetailText = ""
            return
        }

        let selectedNode = (browserSelectedNodeID != nil && browserSelectedNode?.id == browserSelectedNodeID)
            ? browserSelectedNode
            : browserDocument.rootNodes.first(where: { $0.id == browserSelectedNodeID }) ?? browserDocument.rootNodes.first
        browserSelectedNode = selectedNode

        let headerLines = [
            selectedNode?.title,
            selectedNode?.subtitle,
        ].compactMap { $0 }.filter { !$0.isEmpty }

        let detailPreviewRows = (0..<min(selectedNode?.detailCount ?? 0, 24)).map {
            selectedNode?.detailRow(at: $0)
        }.compactMap { $0 }
        let rowLines = detailPreviewRows.map { "\($0.key): \($0.value)" }
        browserDetailText = (headerLines + rowLines).joined(separator: "\n")
    }

    private func updateBrowserHexText() {
        guard let browserDocument else {
            browserHexText = ""
            browserHexRows = []
            browserHexPageLabel = ""
            return
        }

        let selectedNode = browserSelectedNode ?? browserDocument.rootNodes.first
        if selectedNode?.dataRange != nil {
            renderHexSelection(for: selectedNode, in: browserDocument)
            return
        }

        switch browserDocument.hexSource {
        case let .unavailable(reason):
            browserHexText = reason
            browserHexRows = []
            browserHexPageLabel = ""
        case let .file(url, size):
            let pageCount = max(1, Int(ceil(Double(max(size, 1)) / Double(BrowserHexLayout.pageSize))))
            browserHexPageIndex = min(browserHexPageIndex, pageCount - 1)
            browserHexPageLabel = "\(browserHexPageIndex + 1) / \(pageCount)"
            let rows = (try? renderHexPageRows(url: url, pageIndex: browserHexPageIndex, fileSize: size)) ?? []
            browserHexRows = rows
            browserHexText = renderHex(rows)
        }
    }

    private func browserHexPageCount() -> Int {
        guard let browserDocument else { return 1 }
        if browserSelectedNode?.dataRange != nil {
            return 1
        }
        switch browserDocument.hexSource {
        case .unavailable:
            return 1
        case let .file(_, size):
            return max(1, Int(ceil(Double(max(size, 1)) / Double(BrowserHexLayout.pageSize))))
        }
    }

    private func renderHexSelection(for node: BrowserNode?, in browserDocument: BrowserDocument) {
        guard let node else {
            browserHexText = ""
            browserHexRows = []
            browserHexPageLabel = ""
            return
        }

        guard let dataRange = node.dataRange else {
            browserHexText = L10n.workspaceHexUnavailable
            browserHexRows = []
            browserHexPageLabel = ""
            return
        }

        switch browserDocument.hexSource {
        case let .unavailable(reason):
            browserHexText = reason
            browserHexRows = []
            browserHexPageLabel = ""
        case let .file(url, size):
            let clampedOffset = max(0, min(dataRange.offset, max(size - 1, 0)))
            let remaining = max(0, size - clampedOffset)
            let clampedLength = min(dataRange.length, remaining)
            guard clampedLength > 0 else {
                browserHexText = L10n.workspaceHexUnavailable
                browserHexRows = []
                browserHexPageLabel = ""
                return
            }

            let rows = (try? renderHexSelectionRows(
                url: url,
                offset: clampedOffset,
                length: clampedLength,
                rawBaseAddress: Int(node.rawAddress ?? UInt64(clampedOffset)),
                rvaBaseAddress: Int(node.rvaAddress ?? UInt64(clampedOffset)),
                addressMode: browserAddressMode
            )) ?? []
            browserHexRows = rows
            browserHexText = rows.isEmpty ? L10n.workspaceHexUnavailable : renderHex(rows)
            browserHexPageLabel = "\(clampedLength) bytes"
        }
    }

    private func renderHexPageRows(url: URL, pageIndex: Int, fileSize: Int) throws -> [BrowserHexRow] {
        guard fileSize > 0 else { return [] }

        let offset = pageIndex * BrowserHexLayout.pageSize
        let remaining = max(0, fileSize - offset)
        let length = min(BrowserHexLayout.pageSize, remaining)
        guard length > 0 else { return [] }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = handle.readData(ofLength: length)

        return makeHexRows(data: data, baseAddress: offset)
    }

    private func renderHexSelectionRows(
        url: URL,
        offset: Int,
        length: Int,
        rawBaseAddress: Int,
        rvaBaseAddress: Int,
        addressMode: BrowserAddressMode
    ) throws -> [BrowserHexRow] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = handle.readData(ofLength: length)

        let baseAddress = switch addressMode {
        case .raw:
            rawBaseAddress
        case .rva:
            rvaBaseAddress
        }

        return makeHexRows(data: data, baseAddress: baseAddress)
    }

    private func makeHexRows(data: Data, baseAddress: Int) -> [BrowserHexRow] {
        stride(from: 0, to: data.count, by: BrowserHexLayout.bytesPerLine).map { lineOffset in
            let bytes = Array(data[lineOffset..<min(lineOffset + BrowserHexLayout.bytesPerLine, data.count)])
            let hexBytes = bytes.map { String(format: "%02X", $0) }
            let low = hexBytes.prefix(8).joined(separator: " ").padding(toLength: 24, withPad: " ", startingAt: 0)
            let high = Array(hexBytes.dropFirst(8)).joined(separator: " ").padding(toLength: 24, withPad: " ", startingAt: 0)
            let ascii = bytes.map { byte -> Character in
                if byte >= 0x20 && byte <= 0x7E {
                    return Character(UnicodeScalar(byte))
                }
                return "."
            }

            return BrowserHexRow(
                address: String(format: "%08X", baseAddress + lineOffset),
                lowBytes: low,
                highBytes: high,
                ascii: String(ascii)
            )
        }
    }

    private func renderHex(_ rows: [BrowserHexRow]) -> String {
        rows.map { row in
            "\(row.address)  \(row.lowBytes)  \(row.highBytes)  |\(row.ascii)|"
        }.joined(separator: "\n")
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
        EditableSliceViewModel(
            sliceIndex: newIndex,
            installName: existingDraft.installName,
            dylibReferences: slice.dylibReferences.enumerated().map { dylibIndex, reference in
                let draftPath = existingDraft.dylibReferences.first(where: { $0.index == dylibIndex })?.path ?? reference.path
                return EditableDylibReference(index: dylibIndex, command: reference.command, path: draftPath)
            },
            rpaths: existingDraft.rpaths,
            platformMetadata: existingDraft.platformMetadata ?? makePlatformMetadata(for: slice)
        )
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
        case let .slice(index),
             let .header(index),
             let .loadCommands(index),
             let .segments(index),
             let .dylibs(index),
             let .rpaths(index),
             let .symbols(index):
            return analysis.slices.indices.contains(index) ? selection : (analysis.slices.isEmpty ? .document : .slice(0))
        case let .loadCommand(sliceIndex, commandIndex):
            return analysis.slices.indices.contains(sliceIndex) && analysis.slices[sliceIndex].loadCommands.indices.contains(commandIndex)
                ? selection
                : (analysis.slices.isEmpty ? .document : .slice(0))
        case let .segment(sliceIndex, segmentIndex):
            return analysis.slices.indices.contains(sliceIndex) && analysis.slices[sliceIndex].segments.indices.contains(segmentIndex)
                ? selection
                : (analysis.slices.isEmpty ? .document : .slice(0))
        case let .section(sliceIndex, segmentIndex, sectionIndex):
            return analysis.slices.indices.contains(sliceIndex)
                && analysis.slices[sliceIndex].segments.indices.contains(segmentIndex)
                && analysis.slices[sliceIndex].segments[segmentIndex].sections.indices.contains(sectionIndex)
                ? selection
                : (analysis.slices.isEmpty ? .document : .slice(0))
        case let .dylib(sliceIndex, dylibIndex):
            return analysis.slices.indices.contains(sliceIndex) && analysis.slices[sliceIndex].dylibReferences.indices.contains(dylibIndex)
                ? selection
                : (analysis.slices.isEmpty ? .document : .slice(0))
        case let .rpath(sliceIndex, rpathIndex):
            return analysis.slices.indices.contains(sliceIndex) && analysis.slices[sliceIndex].rpaths.indices.contains(rpathIndex)
                ? selection
                : (analysis.slices.isEmpty ? .document : .slice(0))
        case let .symbol(sliceIndex, symbolIndex):
            return analysis.slices.indices.contains(sliceIndex) && analysis.slices[sliceIndex].symbols.indices.contains(symbolIndex)
                ? selection
                : (analysis.slices.isEmpty ? .document : .slice(0))
        case nil:
            return analysis.slices.isEmpty ? .document : .slice(0)
        }
    }

    private func makeOutlineItems(for analysis: DocumentAnalysis, fileURL: URL) -> [OutlineItem] {
        let sliceItems = analysis.slices.enumerated().map { index, slice in
            let loadCommandItems = slice.loadCommands.enumerated().map { commandIndex, command in
                OutlineItem(
                    title: "\(commandIndex). \(commandName(for: command.command))",
                    selection: .loadCommand(sliceIndex: index, commandIndex: commandIndex),
                    children: []
                )
            }

            let segmentItems = slice.segments.enumerated().map { segmentIndex, segment in
                OutlineItem(
                    title: segment.name,
                    selection: .segment(sliceIndex: index, segmentIndex: segmentIndex),
                    children: segment.sections.enumerated().map { sectionIndex, section in
                        OutlineItem(
                            title: "\(section.segmentName).\(section.name)",
                            selection: .section(sliceIndex: index, segmentIndex: segmentIndex, sectionIndex: sectionIndex),
                            children: []
                        )
                    }
                )
            }

            let dylibItems = slice.dylibReferences.enumerated().map { dylibIndex, dylib in
                OutlineItem(
                    title: dylib.path,
                    selection: .dylib(sliceIndex: index, dylibIndex: dylibIndex),
                    children: []
                )
            }

            let rpathItems = slice.rpaths.enumerated().map { rpathIndex, rpath in
                OutlineItem(
                    title: rpath,
                    selection: .rpath(sliceIndex: index, rpathIndex: rpathIndex),
                    children: []
                )
            }

            let symbolItems = slice.symbols.prefix(200).enumerated().map { symbolIndex, symbol in
                OutlineItem(
                    title: symbol.name.isEmpty ? "(anonymous)" : symbol.name,
                    selection: .symbol(sliceIndex: index, symbolIndex: symbolIndex),
                    children: []
                )
            }

            return OutlineItem(
                title: L10n.viewerSliceOutlineTitle(
                    index: index,
                    bitness: slice.is64Bit ? L10n.viewerBitness64 : L10n.viewerBitness32,
                    commandCount: slice.loadCommandCount
                ),
                selection: .slice(index),
                children: [
                    OutlineItem(title: L10n.viewerHeaderSection, selection: .header(index), children: []),
                    OutlineItem(title: L10n.viewerLoadCommandsSection, selection: .loadCommands(index), children: loadCommandItems),
                    OutlineItem(title: L10n.viewerSegmentsSection, selection: .segments(index), children: segmentItems),
                    OutlineItem(title: L10n.viewerDylibsSection, selection: .dylibs(index), children: dylibItems),
                    OutlineItem(title: L10n.viewerRPathsSection, selection: .rpaths(index), children: rpathItems),
                    OutlineItem(title: L10n.viewerSymbolsSection, selection: .symbols(index), children: symbolItems),
                ]
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
        guard let selectedIndex = selectedSliceIndex() else { return nil }
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
                kind = L10n.viewerInstallNameDiffKind
            case .dylib:
                kind = L10n.viewerDylibDiffKind
            case .rpath:
                kind = L10n.viewerRPathDiffKind
            case .platform:
                kind = L10n.viewerPlatformDiffKind
            case .segmentProtection:
                kind = L10n.viewerSegmentProtectionDiffKind
            case .codeSignature:
                kind = L10n.viewerCodeSignatureDiffKind
            }

            return L10n.viewerDiffEntry(
                kind: kind,
                originalValue: entry.originalValue ?? L10n.viewerNone,
                updatedValue: entry.updatedValue ?? L10n.viewerRemoved
            )
        }.joined(separator: "\n")
    }

    private func applyDraft(_ draft: EditableSliceViewModel) {
        editableSlicesByIndex[draft.sliceIndex] = draft
        if let selectedIndex = selectedSliceIndex(), selectedIndex == draft.sliceIndex {
            editableSlice = draft
        }
        previewText = ""
    }

    private func selectedSliceIndex() -> Int? {
        switch selection {
        case let .slice(index),
             let .header(index),
             let .loadCommands(index),
             let .segments(index),
             let .dylibs(index),
             let .rpaths(index),
             let .symbols(index):
            return index
        case let .loadCommand(sliceIndex, _),
             let .segment(sliceIndex, _),
             let .dylib(sliceIndex, _),
             let .rpath(sliceIndex, _),
             let .symbol(sliceIndex, _):
            return sliceIndex
        case let .section(sliceIndex, _, _):
            return sliceIndex
        case .document, nil:
            return nil
        }
    }

    private func refreshEditableSlice() {
        guard let analysis else {
            editableSlice = nil
            selectedSliceSummary = nil
            previewText = ""
            return
        }

        guard let sliceIndex = selectedSliceIndex() else {
            editableSlice = nil
            selectedSliceSummary = nil
            previewText = ""
            return
        }

        guard analysis.slices.indices.contains(sliceIndex), let draft = editableSlicesByIndex[sliceIndex] else {
            editableSlice = nil
            selectedSliceSummary = nil
            previewText = ""
            return
        }

        selectedSliceSummary = analysis.slices[sliceIndex]
        editableSlice = draft
        previewText = ""
    }

    private func slice(at index: Int, in analysis: DocumentAnalysis) -> SliceSummary? {
        analysis.slices.indices.contains(index) ? analysis.slices[index] : nil
    }

    private func commandName(for command: UInt32) -> String {
        switch command {
        case 0x1:
            return "LC_SEGMENT"
        case 0x19:
            return "LC_SEGMENT_64"
        case 0xD:
            return "LC_ID_DYLIB"
        case 0xC:
            return "LC_LOAD_DYLIB"
        case 0x80000018:
            return "LC_LOAD_WEAK_DYLIB"
        case 0x8000001F:
            return "LC_REEXPORT_DYLIB"
        case 0x8000001C:
            return "LC_RPATH"
        case 0x32:
            return "LC_BUILD_VERSION"
        case 0x24:
            return "LC_VERSION_MIN_MACOSX"
        case 0x25:
            return "LC_VERSION_MIN_IPHONEOS"
        case 0x2F:
            return "LC_VERSION_MIN_TVOS"
        case 0x30:
            return "LC_VERSION_MIN_WATCHOS"
        case 0x2:
            return "LC_SYMTAB"
        case 0x1B:
            return "LC_UUID"
        case 0x1D:
            return "LC_CODE_SIGNATURE"
        case 0x21:
            return "LC_ENCRYPTION_INFO"
        case 0x2C:
            return "LC_ENCRYPTION_INFO_64"
        default:
            return "Load Command 0x" + String(command, radix: 16, uppercase: true)
        }
    }

    private func formatHex(_ value: UInt32) -> String {
        "0x" + String(value, radix: 16, uppercase: true)
    }

    private func formatHex(_ value: UInt64) -> String {
        "0x" + String(value, radix: 16, uppercase: true)
    }

    private func formatPlatform(_ platform: MachOPlatform?) -> String {
        guard let platform else { return "n/a" }
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
            return "macCatalyst"
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
            return "Firmware"
        case .sepOS:
            return "sepOS"
        case let .unknown(rawValue):
            return "unknown(\(rawValue))"
        }
    }

    private func formatProtection(_ rawValue: Int32) -> String {
        var components = [String]()
        if rawValue & 1 != 0 { components.append("r") }
        if rawValue & 2 != 0 { components.append("w") }
        if rawValue & 4 != 0 { components.append("x") }
        return components.isEmpty ? "-" : components.joined()
    }
}

private enum WorkspaceEditingError: Error {
    case noDocumentLoaded
    case invalidSelection
    case noPendingEdits
}

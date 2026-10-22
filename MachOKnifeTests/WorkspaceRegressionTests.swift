import AppKit
import CoreMachO
import Foundation
import MachOKnifeKit
import Testing
@testable import MachOKnife

/// 工作区（主窗口 + WorkspaceViewModel）在代码审查中修复的问题对应的回归测试。
@MainActor
struct WorkspaceRegressionTests {
    @Test("loading copy is re-localized when the language changes during a staged load")
    func loadingDetailTextFollowsLanguageChanges() async throws {
        let localization = TestLocalizationOverride(language: .english)
        defer {
            localization.restore()
        }

        let fixtureURL = try TestUI.makeFixtureCopy()
        let budget = AnalysisBudget(
            maximumFileSize: 1,
            maximumSymbolCount: .max,
            maximumStringTableSize: .max,
            maximumEstimatedNodeCount: .max
        )
        // 加载器一直阻塞到测试放行，保证切换语言时仍处于 loading 状态（不依赖计时）。
        let gate = DispatchSemaphore(value: 0)
        defer {
            // 即使断言提前失败也要放行后台加载，避免遗留阻塞的线程。
            gate.signal()
        }
        let viewModel = WorkspaceViewModel(
            analysisBudget: budget,
            documentLoadService: WorkspaceDocumentLoadService { url, analysisBudget in
                gate.wait()
                let scan = try MachOContainer.scan(at: url)
                return WorkspaceDocumentLoadService.MetadataStage(
                    scan: scan,
                    decision: analysisBudget.classify(scan: scan),
                    analysis: try DocumentAnalysisService().analyze(scan: scan)
                )
            }
        )

        #expect(viewModel.openDocument(at: fixtureURL))
        #expect(viewModel.loadingState == .loading)
        let englishLoadingText = viewModel.loadingDetailText
        #expect(englishLoadingText == L10n.workspaceLoadingAnalyzing)

        localization.settings.language = .simplifiedChinese
        viewModel.reloadPresentation()

        #expect(viewModel.loadingDetailText == L10n.workspaceLoadingAnalyzing)
        #expect(viewModel.loadingDetailText != englishLoadingText)

        gate.signal()
        let deadline = Date().addingTimeInterval(5)
        while viewModel.loadingState == .loading, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(viewModel.loadingState == .degraded)
        #expect(viewModel.loadingDetailText == L10n.workspaceLoadingDeferredCollections)

        localization.settings.language = .english
        viewModel.reloadPresentation()

        #expect(viewModel.loadingDetailText == L10n.workspaceLoadingDeferredCollections)
        #expect(viewModel.loadingDetailText.hasPrefix("Large-file mode"))
    }

    @Test("hex page label and command sizes use the localized byte unit")
    func byteCountsAreLocalized() throws {
        let localization = TestLocalizationOverride(language: .simplifiedChinese)
        defer {
            localization.restore()
        }

        let viewModel = WorkspaceViewModel()
        #expect(viewModel.openDocument(at: try TestUI.makeFixtureCopy()))

        let segmentNode = try #require(findBrowserNode(in: viewModel.browserOutlineRootNodes) { node in
            node.title == "__TEXT" && node.dataRange != nil
        })
        viewModel.selectBrowserNode(segmentNode)

        #expect(viewModel.browserHexPageLabel.contains("字节"))
        #expect(viewModel.browserHexPageLabel.contains("bytes") == false)

        viewModel.select(.loadCommands(0))
        #expect(viewModel.detailText.contains("字节"))
        #expect(viewModel.detailText.contains(" bytes") == false)
    }

    @Test("deferred symbol message is localized instead of falling back to the English text")
    func deferredSymbolsMessageIsLocalized() {
        let localization = TestLocalizationOverride(language: .simplifiedChinese)
        defer {
            localization.restore()
        }

        let message = L10n.viewerDeferredSymbolsMessage(42)
        #expect(message.contains("42"))
        #expect(message.contains("Showing the metadata shell") == false)

        localization.settings.language = .traditionalChinese
        #expect(L10n.viewerDeferredSymbolsMessage(42).contains("42"))
        #expect(L10n.viewerDeferredSymbolsMessage(42) != message)
    }

    @Test("closing a document resets browser, loading and address-mode state")
    func closeDocumentResetsBrowserState() throws {
        let viewModel = WorkspaceViewModel()
        #expect(viewModel.openDocument(at: try TestUI.makeFixtureCopy()))
        viewModel.setBrowserAddressMode(.rva)
        #expect(viewModel.browserDocument != nil)
        #expect(viewModel.loadingState == .ready)

        viewModel.closeCurrentDocument()

        #expect(viewModel.browserDocument == nil)
        #expect(viewModel.browserOutlineRootNodes.isEmpty)
        #expect(viewModel.browserSelectedNode == nil)
        #expect(viewModel.browserSelectedNodeID == nil)
        #expect(viewModel.browserAddressMode == .raw)
        #expect(viewModel.browserHexRows.isEmpty)
        #expect(viewModel.browserHexPageLabel.isEmpty)
        #expect(viewModel.loadingState == .idle)
        #expect(viewModel.loadingDetailText.isEmpty)
    }

    @Test("opening an unreadable file reports an error without a loaded document")
    func openingInvalidFileReportsError() throws {
        let url = try makeInvalidFile()
        let viewModel = WorkspaceViewModel()

        #expect(viewModel.openDocument(at: url) == false)
        #expect(viewModel.loadingState == .error)
        #expect(viewModel.errorMessage?.isEmpty == false)
        #expect(viewModel.currentFileURL == url)
        #expect(viewModel.hasLoadedDocument == false)
    }

    @Test("open error stays visible in the detail pane after a language change")
    func openErrorSurvivesLanguageChange() throws {
        let localization = TestLocalizationOverride(language: .english)
        defer {
            localization.restore()
        }

        let controller = MainWindowController()
        _ = try #require(controller.window)
        let url = try makeInvalidFile()

        #expect(controller.openDocument(at: url) == false)
        TestUI.pumpRunLoop()
        let errorMessage = try #require(controller.viewModel.errorMessage)
        let textsBeforeLanguageChange = TestUI.visibleTexts(in: controller.window?.contentView)
        #expect(textsBeforeLanguageChange.contains(errorMessage))

        localization.settings.language = .simplifiedChinese
        TestUI.pumpRunLoop()

        let textsAfterLanguageChange = TestUI.visibleTexts(in: controller.window?.contentView)
        #expect(textsAfterLanguageChange.contains(errorMessage))
        controller.window?.close()
    }

    @Test("structure search is cleared when another document is opened")
    func searchIsClearedWhenDocumentChanges() throws {
        let controller = MainWindowController()
        _ = try #require(controller.window)
        #expect(controller.openDocument(at: try TestUI.makeFixtureCopy()))
        TestUI.pumpRunLoop()

        let searchFields = TestUI.descendants(of: controller.window?.contentView, ofType: NSSearchField.self)
        let searchField = try #require(searchFields.first)
        searchField.stringValue = "no-such-node-in-this-binary"
        searchField.sendAction(searchField.action, to: searchField.target)
        TestUI.pumpRunLoop()

        #expect(controller.openDocument(at: try TestUI.makeFixtureCopy(named: "libSecond.dylib")))
        TestUI.pumpRunLoop()

        #expect(searchField.stringValue.isEmpty)
        let outlineViews = TestUI.descendants(of: controller.window?.contentView, ofType: NSOutlineView.self)
        let outlineView = try #require(outlineViews.first)
        #expect(outlineView.numberOfRows > 0)
        controller.window?.close()
    }

    @Test("workspace tables support the standard Copy command only when a row is selected")
    func tablesValidateCopyCommand() throws {
        let controller = MainWindowController()
        _ = try #require(controller.window)
        #expect(controller.openDocument(at: try TestUI.makeFixtureCopy()))
        TestUI.pumpRunLoop()

        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let tables = TestUI.descendants(of: controller.window?.contentView, ofType: NSTableView.self)
        // 结构树（NSOutlineView）+ 详情表 + 十六进制表。
        #expect(tables.count >= 3)

        for table in tables {
            #expect(table.responds(to: #selector(NSText.copy(_:))))
            table.deselectAll(nil)
            #expect(table.validateUserInterfaceItem(copyItem) == false)
        }

        let detailTable = try #require(tables.first { ($0 is NSOutlineView) == false && $0.numberOfRows > 0 })
        detailTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        #expect(detailTable.validateUserInterfaceItem(copyItem))
        controller.window?.close()
    }

    // MARK: - Helpers

    private func makeInvalidFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("not-a-macho.txt")
        try "definitely not a Mach-O file".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func findBrowserNode(in nodes: [BrowserNode], where matches: (BrowserNode) -> Bool) -> BrowserNode? {
        for node in nodes {
            if matches(node) {
                return node
            }
            if let child = findBrowserNode(in: node.children, where: matches) {
                return child
            }
        }
        return nil
    }
}

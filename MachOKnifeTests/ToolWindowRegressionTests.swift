import AppKit
import Foundation
import Testing
@testable import MachOKnife

/// 工具窗口在代码审查中修复的问题对应的回归测试。
@MainActor
struct ToolWindowRegressionTests {
    @Test("Mach-O summary analyzes off the main thread and then shows the report")
    func summaryAnalyzesInBackground() async throws {
        let localization = TestLocalizationOverride(language: .english)
        defer {
            localization.restore()
        }

        let controller = MachOSummaryWindowController()
        let fixtureURL = try TestUI.makeFixtureCopy()

        controller.loadInput(fixtureURL)

        // 结果必须经由主线程回调才能生效，因此在让出主线程之前一定处于“分析中”状态，
        // 证明分析没有在主线程上同步执行。
        #expect(controller.isAnalyzing)
        #expect(controller.reportText == L10n.summaryRunningStatus)

        let deadline = Date().addingTimeInterval(10)
        while controller.isAnalyzing, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(controller.isAnalyzing == false)
        #expect(controller.reportText != L10n.summaryRunningStatus)
        #expect(controller.reportText.isEmpty == false)
        #expect(controller.reportText != L10n.summaryIdleStatus)
        controller.window?.close()
    }

    @Test("contamination idle hint is re-localized after a language change")
    func contaminationIdleTextFollowsLanguage() throws {
        let localization = TestLocalizationOverride(language: .english)
        defer {
            localization.restore()
        }

        let controller = BinaryContaminationWindowController()
        let textViews = TestUI.descendants(of: controller.window?.contentView, ofType: NSTextView.self)
        let reportTextView = try #require(textViews.first)
        let englishIdle = L10n.contaminationIdleStatus
        #expect(reportTextView.string == englishIdle)

        localization.settings.language = .simplifiedChinese
        TestUI.pumpRunLoop()

        #expect(reportTextView.string == L10n.contaminationIdleStatus)
        #expect(reportTextView.string != englishIdle)
        controller.window?.close()
    }
}

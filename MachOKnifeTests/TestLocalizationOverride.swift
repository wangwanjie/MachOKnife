import AppKit
import Foundation
@testable import MachOKnife

/// 在测试中临时把 L10n 指向一份独立的 AppSettings，便于切换界面语言；用完后调用 `restore()` 恢复。
@MainActor
final class TestLocalizationOverride {
    let settings: AppSettings
    private let suiteName: String
    private let defaults: UserDefaults
    private let originalSettingsProvider: () -> AppSettings
    private let originalBundleProvider: () -> Bundle

    init(language: AppLanguage) {
        suiteName = "MachOKnifeTests.LocalizationOverride.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settings = AppSettings(defaults: defaults)
        settings.language = language

        originalSettingsProvider = L10n.settingsProvider
        originalBundleProvider = L10n.bundleProvider
        let settings = settings
        L10n.settingsProvider = { settings }
        L10n.bundleProvider = { .main }
    }

    func restore() {
        L10n.settingsProvider = originalSettingsProvider
        L10n.bundleProvider = originalBundleProvider
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
enum TestUI {
    /// 运行主线程 RunLoop 一段时间，让 Combine 的 `receive(on: RunLoop.main)` 与通知回调得以执行。
    static func pumpRunLoop(for duration: TimeInterval = 0.2) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }

    /// 递归收集视图树中所有指定类型的子视图（含隐藏视图）。
    static func descendants<T: NSView>(of view: NSView?, ofType type: T.Type) -> [T] {
        guard let view else {
            return []
        }
        var result: [T] = []
        if let match = view as? T {
            result.append(match)
        }
        for subview in view.subviews {
            result.append(contentsOf: descendants(of: subview, ofType: type))
        }
        return result
    }

    /// 收集当前可见（自身及祖先均未隐藏）的文本框文字。
    static func visibleTexts(in view: NSView?) -> [String] {
        guard let view, view.isHidden == false else {
            return []
        }
        var texts: [String] = []
        if let textField = view as? NSTextField {
            let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty == false {
                texts.append(text)
            }
        }
        for subview in view.subviews {
            texts.append(contentsOf: visibleTexts(in: subview))
        }
        return texts
    }

    static func repositoryRoot() -> URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 复制一份可编辑的 dylib 测试样本到独立临时目录。
    static func makeFixtureCopy(named name: String = "libCLIEditable.dylib") throws -> URL {
        let sourceURL = repositoryRoot().appendingPathComponent("Resources/Fixtures/cli/libCLIEditable.dylib")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destinationURL = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }
}

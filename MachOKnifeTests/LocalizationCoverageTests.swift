import Foundation
import Testing

/// 校验 L10n 中使用的每个本地化 key 在三种语言的 Localizable.strings 中都存在，
/// 且各语言的格式化占位符一致（缺 key 时界面会静默回退到英文，占位符不一致则可能崩溃或显示错乱）。
struct LocalizationCoverageTests {
    private static let languages = ["en", "zh-Hans", "zh-Hant"]

    @Test("every L10n key exists in en, zh-Hans and zh-Hant Localizable.strings")
    func everyKeyExistsInAllLanguages() throws {
        let codeKeys = try Self.keysUsedByL10n()
        #expect(codeKeys.count > 300, "L10n key 提取结果异常：\(codeKeys.count)")

        for language in Self.languages {
            let entries = try Self.stringsEntries(language: language)
            let missing = codeKeys.subtracting(entries.keys).sorted()
            #expect(missing.isEmpty, "\(language) 缺少 key：\(missing)")
        }
    }

    @Test("strings files define the same keys without duplicates")
    func stringsFilesAreConsistent() throws {
        let english = try Self.stringsEntries(language: "en")
        for language in Self.languages {
            let rawKeys = try Self.rawKeys(language: language)
            let duplicates = Dictionary(grouping: rawKeys, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
            #expect(duplicates.isEmpty, "\(language) 存在重复 key：\(duplicates)")

            let entries = try Self.stringsEntries(language: language)
            #expect(Set(entries.keys) == Set(english.keys), "\(language) 与 en 的 key 集合不一致")
        }
    }

    @Test("translations keep the same format placeholders as English")
    func translationsKeepFormatPlaceholders() throws {
        let english = try Self.stringsEntries(language: "en")
        for language in Self.languages where language != "en" {
            let translated = try Self.stringsEntries(language: language)
            for (key, englishValue) in english {
                guard let translatedValue = translated[key] else {
                    continue
                }
                #expect(
                    Self.placeholders(in: translatedValue) == Self.placeholders(in: englishValue),
                    "\(language) 中 \(key) 的占位符与英文不一致"
                )
            }
        }
    }

    // MARK: - Helpers

    private static func repositoryRoot() -> URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 从 L10n.swift 中提取 `text("key", …)` / `format("key", …)` 使用的 key。
    private static func keysUsedByL10n() throws -> Set<String> {
        let sourceURL = repositoryRoot().appendingPathComponent("MachOKnifeApp/Localization/L10n.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"(?:text|format)\(\s*"([^"]+)""#)
        let range = NSRange(source.startIndex..., in: source)
        let keys = regex.matches(in: source, range: range).compactMap { match -> String? in
            guard let keyRange = Range(match.range(at: 1), in: source) else {
                return nil
            }
            return String(source[keyRange])
        }
        return Set(keys)
    }

    private static func stringsURL(language: String) -> URL {
        repositoryRoot().appendingPathComponent("Resources/Localization/\(language).lproj/Localizable.strings")
    }

    private static func stringsEntries(language: String) throws -> [String: String] {
        let data = try Data(contentsOf: stringsURL(language: language))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return plist as? [String: String] ?? [:]
    }

    /// PropertyListSerialization 会静默合并重复 key，因此单独按行提取原始 key 用于查重。
    private static func rawKeys(language: String) throws -> [String] {
        let contents = try String(contentsOf: stringsURL(language: language), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"^\s*"((?:[^"\\]|\\.)+)"\s*="#, options: [.anchorsMatchLines])
        let range = NSRange(contents.startIndex..., in: contents)
        return regex.matches(in: contents, range: range).compactMap { match -> String? in
            guard let keyRange = Range(match.range(at: 1), in: contents) else {
                return nil
            }
            return String(contents[keyRange])
        }
    }

    /// 提取格式化占位符（如 %@、%ld、%1$@），按出现位置无关的方式排序后比较。
    private static func placeholders(in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"%(?:\d+\$)?(?:@|l{0,2}[dDuUxXfgs])"#) else {
            return []
        }
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).compactMap { match -> String? in
            guard let placeholderRange = Range(match.range, in: value) else {
                return nil
            }
            return String(value[placeholderRange])
        }.sorted()
    }
}

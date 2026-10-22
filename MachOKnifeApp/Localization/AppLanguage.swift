import Foundation

enum AppLanguage: String, CaseIterable {
    case system
    case english
    case simplifiedChinese
    case traditionalChinese

    var localizationIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .traditionalChinese:
            return "zh-Hant"
        }
    }

    static func resolve(preferredLanguages: [String]) -> AppLanguage {
        for identifier in preferredLanguages {
            if let language = supportedLanguage(for: identifier) {
                return language
            }
        }

        return .english
    }

    private static func supportedLanguage(for identifier: String) -> AppLanguage? {
        let normalized = identifier.lowercased()

        if normalized.hasPrefix("zh") {
            // 按 BCP 47 子标签判断，避免子串误判；显式的书写系统（Hans/Hant）优先于地区，
            // 例如 "zh-Hans-HK"（香港地区的简体中文）应解析为简体，而不是按地区判为繁体。
            let subtags = normalized
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .map(String.init)
            if subtags.contains("hans") {
                return .simplifiedChinese
            }
            if subtags.contains("hant") {
                return .traditionalChinese
            }
            let traditionalRegions: Set<String> = ["tw", "hk", "mo"]
            if subtags.contains(where: { traditionalRegions.contains($0) }) {
                return .traditionalChinese
            }
            return .simplifiedChinese
        }

        if normalized.hasPrefix("en") {
            return .english
        }

        return nil
    }
}

enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark
}

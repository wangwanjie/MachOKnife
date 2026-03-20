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
            if normalized.contains("hant") || normalized.contains("tw") || normalized.contains("hk") || normalized.contains("mo") {
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

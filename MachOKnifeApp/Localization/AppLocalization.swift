import Foundation

struct AppLocalization {
    private let bundle: Bundle
    private let language: AppLanguage

    init(bundle: Bundle = .main, language: AppLanguage) {
        self.bundle = bundle
        self.language = language
    }

    func string(_ key: String, fallback: String) -> String {
        let localizationBundle = localizedBundle()
        let localizedValue = localizationBundle.localizedString(forKey: key, value: fallback, table: "Localizable")
        return localizedValue == key ? fallback : localizedValue
    }

    // When users override the language in preferences, we load the matching
    // `.lproj` bundle directly instead of relying on the process locale.
    private func localizedBundle() -> Bundle {
        guard
            let identifier = language.localizationIdentifier,
            let bundlePath = bundle.path(forResource: identifier, ofType: "lproj"),
            let localizedBundle = Bundle(path: bundlePath)
        else {
            return bundle
        }

        return localizedBundle
    }
}

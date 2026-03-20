import Foundation
import AppKit

final class AppSettings {
    static let shared = AppSettings()
    static let didChangeNotification = Notification.Name("cn.vanjay.MachOKnife.AppSettingsDidChange")
    static let defaultRecentFilesLimit = 50

    private enum Keys {
        static let language = "app.language"
        static let theme = "app.theme"
        static let recentFilesLimit = "app.recentFilesLimit"
        static let cliInstallDirectoryBookmark = "app.cliInstallDirectoryBookmark"
        static let cliInstallDirectoryPath = "app.cliInstallDirectoryPath"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var language: AppLanguage {
        get {
            AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.language)
            notifyDidChange()
        }
    }

    var theme: AppTheme {
        get {
            AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.theme)
            notifyDidChange()
        }
    }

    var recentFilesLimit: Int {
        get {
            let storedValue = defaults.integer(forKey: Keys.recentFilesLimit)
            return storedValue > 0 ? storedValue : Self.defaultRecentFilesLimit
        }
        set {
            defaults.set(max(1, newValue), forKey: Keys.recentFilesLimit)
            notifyDidChange()
        }
    }

    func setCLIInstallDirectory(_ url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmarkData, forKey: Keys.cliInstallDirectoryBookmark)
        defaults.set(url.path, forKey: Keys.cliInstallDirectoryPath)
        notifyDidChange()
    }

    func clearCLIInstallDirectory() {
        defaults.removeObject(forKey: Keys.cliInstallDirectoryBookmark)
        defaults.removeObject(forKey: Keys.cliInstallDirectoryPath)
        notifyDidChange()
    }

    func cliInstallDirectoryURL() throws -> URL? {
        if let bookmarkData = defaults.data(forKey: Keys.cliInstallDirectoryBookmark) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }

        guard let path = defaults.string(forKey: Keys.cliInstallDirectoryPath), path.isEmpty == false else {
            return nil
        }

        return URL(filePath: path, directoryHint: .isDirectory)
    }

    func resolvedLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        switch language {
        case .system:
            return AppLanguage.resolve(preferredLanguages: preferredLanguages)
        default:
            return language
        }
    }

    func effectiveAppearance() -> NSAppearance? {
        switch theme {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }

    private func notifyDidChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}

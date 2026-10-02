import Foundation
import AppKit

final class AppSettings {
    static let shared = AppSettings()
    static let didChangeNotification = Notification.Name("cn.vanjay.MachOKnife.AppSettingsDidChange")
    static let defaultRecentFilesLimit = 50
    /// `userInfo` key of `didChangeNotification` holding the `Change` (raw value) that was made.
    static let changeUserInfoKey = "change"

    enum Change: String {
        case language
        case theme
        case recentFilesLimit
        case cliInstallDirectory
        case cliExecutable

        var affectsCLIInstallation: Bool {
            self == .cliInstallDirectory || self == .cliExecutable
        }
    }

    /// The change carried by a `didChangeNotification`, if any.
    static func change(from notification: Notification) -> Change? {
        (notification.userInfo?[changeUserInfoKey] as? String).flatMap(Change.init(rawValue:))
    }

    private enum Keys {
        static let language = "app.language"
        static let theme = "app.theme"
        static let recentFilesLimit = "app.recentFilesLimit"
        static let cliInstallDirectoryBookmark = "app.cliInstallDirectoryBookmark"
        static let cliInstallDirectoryPath = "app.cliInstallDirectoryPath"
        static let cliInstalledExecutablePath = "app.cliInstalledExecutablePath"
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
            notifyDidChange(.language)
        }
    }

    var theme: AppTheme {
        get {
            AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.theme)
            notifyDidChange(.theme)
        }
    }

    var recentFilesLimit: Int {
        get {
            let storedValue = defaults.integer(forKey: Keys.recentFilesLimit)
            return storedValue > 0 ? storedValue : Self.defaultRecentFilesLimit
        }
        set {
            defaults.set(max(1, newValue), forKey: Keys.recentFilesLimit)
            notifyDidChange(.recentFilesLimit)
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
        notifyDidChange(.cliInstallDirectory)
    }

    func clearCLIInstallDirectory() {
        defaults.removeObject(forKey: Keys.cliInstallDirectoryBookmark)
        defaults.removeObject(forKey: Keys.cliInstallDirectoryPath)
        notifyDidChange(.cliInstallDirectory)
    }

    func setLastKnownCLIExecutablePath(_ path: String) {
        defaults.set(path, forKey: Keys.cliInstalledExecutablePath)
        notifyDidChange(.cliExecutable)
    }

    func clearLastKnownCLIExecutablePath() {
        defaults.removeObject(forKey: Keys.cliInstalledExecutablePath)
        notifyDidChange(.cliExecutable)
    }

    func lastKnownCLIExecutablePath() -> String? {
        let path = defaults.string(forKey: Keys.cliInstalledExecutablePath)
        return path?.isEmpty == false ? path : nil
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
                if isStale {
                    refreshStaleCLIInstallDirectoryBookmark(for: url)
                }
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

    /// Re-creates a stale security-scoped bookmark so it keeps resolving. Access is started first
    /// (a security-scoped bookmark can only be created while the scope is active); if anything
    /// fails the existing bookmark data is kept rather than replaced with a non-scoped one.
    private func refreshStaleCLIInstallDirectoryBookmark(for url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let refreshedBookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }

        defaults.set(refreshedBookmark, forKey: Keys.cliInstallDirectoryBookmark)
        defaults.set(url.path, forKey: Keys.cliInstallDirectoryPath)
    }

    private func notifyDidChange(_ change: Change) {
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: self,
            userInfo: [Self.changeUserInfoKey: change.rawValue]
        )
    }
}

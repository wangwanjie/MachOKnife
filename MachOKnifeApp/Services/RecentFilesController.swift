import Foundation
import MachOKnifeDB

final class RecentFilesController {
    struct BookmarkResolutionResult {
        let url: URL
        let isStale: Bool
    }

    typealias BookmarkDataProvider = (URL) throws -> Data
    typealias BookmarkResolver = (Data) throws -> BookmarkResolutionResult

    private enum Keys {
        static let recentFileBookmarks = "app.recentFileBookmarks"
    }

    private let settings: AppSettings
    private let database: AppDatabase
    private let defaults: UserDefaults
    private let bookmarkDataProvider: BookmarkDataProvider
    private let bookmarkResolver: BookmarkResolver

    init(
        settings: AppSettings = .shared,
        databaseURL: URL? = nil,
        defaults: UserDefaults = .standard,
        bookmarkDataProvider: @escaping BookmarkDataProvider = RecentFilesController.makeBookmarkData(for:),
        bookmarkResolver: @escaping BookmarkResolver = RecentFilesController.resolveBookmarkData(_:)
    ) throws {
        self.settings = settings
        self.defaults = defaults
        self.bookmarkDataProvider = bookmarkDataProvider
        self.bookmarkResolver = bookmarkResolver

        let resolvedDatabaseURL = try databaseURL ?? Self.defaultDatabaseURL()
        try FileManager.default.createDirectory(
            at: resolvedDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.database = try AppDatabase(path: resolvedDatabaseURL.path)
    }

    func recordOpen(url: URL, openedAt: Date = Date()) throws {
        try makeStore().recordAccess(to: url, openedAt: openedAt)
        // Bookmark persistence should improve reopen behavior, not block recent-file recording.
        try? storeBookmark(for: url)
    }

    func recentFileURLs() throws -> [URL] {
        let records = try makeStore()
            .fetchRecentFiles()
            .prefix(settings.recentFilesLimit)
        pruneBookmarks(validPaths: Set(records.map(\.path)))
        return records.map(resolveRecentFileURL(for:))
    }

    private func makeStore() -> RecentFilesStore {
        RecentFilesStore(appDatabase: database, maxEntries: settings.recentFilesLimit)
    }

    private func resolveRecentFileURL(for record: RecentFileRecord) -> URL {
        guard let bookmarkData = recentFileBookmarks()[record.path] else {
            return URL(fileURLWithPath: record.path)
        }

        do {
            let resolved = try bookmarkResolver(bookmarkData)
            if resolved.isStale {
                try? storeBookmark(for: resolved.url, pathKey: record.path)
            }
            return resolved.url
        } catch {
            removeBookmark(forPath: record.path)
            return URL(fileURLWithPath: record.path)
        }
    }

    private func storeBookmark(for url: URL, pathKey: String? = nil) throws {
        var bookmarks = recentFileBookmarks()
        let bookmarkData = try bookmarkDataProvider(url)
        bookmarks[pathKey ?? url.path] = bookmarkData
        defaults.set(bookmarks, forKey: Keys.recentFileBookmarks)
    }

    private func removeBookmark(forPath path: String) {
        var bookmarks = recentFileBookmarks()
        bookmarks.removeValue(forKey: path)
        defaults.set(bookmarks, forKey: Keys.recentFileBookmarks)
    }

    private func pruneBookmarks(validPaths: Set<String>) {
        var bookmarks = recentFileBookmarks()
        let invalidPaths = Set(bookmarks.keys).subtracting(validPaths)
        guard invalidPaths.isEmpty == false else { return }
        invalidPaths.forEach { bookmarks.removeValue(forKey: $0) }
        defaults.set(bookmarks, forKey: Keys.recentFileBookmarks)
    }

    private func recentFileBookmarks() -> [String: Data] {
        defaults.dictionary(forKey: Keys.recentFileBookmarks) as? [String: Data] ?? [:]
    }

    private static func defaultDatabaseURL() throws -> URL {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return applicationSupportURL
            .appendingPathComponent("MachOKnife", isDirectory: true)
            .appendingPathComponent("MachOKnife.sqlite")
    }

    nonisolated static func makeBookmarkData(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    nonisolated static func resolveBookmarkData(_ data: Data) throws -> BookmarkResolutionResult {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return BookmarkResolutionResult(url: url, isStale: isStale)
    }
}

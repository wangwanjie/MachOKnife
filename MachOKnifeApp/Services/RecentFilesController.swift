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
    private let staleBookmarkRefresher: BookmarkDataProvider

    init(
        settings: AppSettings = .shared,
        databaseURL: URL? = nil,
        defaults: UserDefaults = .standard,
        bookmarkDataProvider: @escaping BookmarkDataProvider = RecentFilesController.makeBookmarkData(for:),
        bookmarkResolver: @escaping BookmarkResolver = RecentFilesController.resolveBookmarkData(_:),
        staleBookmarkRefresher: @escaping BookmarkDataProvider = RecentFilesController.makeRefreshedSecurityScopedBookmarkData(for:)
    ) throws {
        self.settings = settings
        self.defaults = defaults
        self.bookmarkDataProvider = bookmarkDataProvider
        self.bookmarkResolver = bookmarkResolver
        self.staleBookmarkRefresher = staleBookmarkRefresher

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

    /// 清空最近文件列表：删除数据库中的全部记录，并丢弃为这些文件保存的安全作用域书签，
    /// 避免已从菜单移除的文件仍保留沙盒访问凭据。
    func clearRecentFiles() throws {
        try makeStore().removeAll()
        defaults.removeObject(forKey: Keys.recentFileBookmarks)
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
                refreshStaleBookmark(for: resolved.url, pathKey: record.path)
            }
            return resolved.url
        } catch {
            // 解析失败不一定代表书签已失效：书签以 `.withoutMounting` 解析，文件所在的外接/网络卷
            // 暂未挂载时同样会失败。保留书签以便卷重新挂载后恢复沙盒访问权限；
            // 书签会随记录被淘汰时由 `pruneBookmarks` 清理。
            return URL(fileURLWithPath: record.path)
        }
    }

    private func storeBookmark(for url: URL, pathKey: String? = nil) throws {
        var bookmarks = recentFileBookmarks()
        let bookmarkData = try bookmarkDataProvider(url)
        bookmarks[pathKey ?? url.path] = bookmarkData
        defaults.set(bookmarks, forKey: Keys.recentFileBookmarks)
    }

    /// Replaces a stale bookmark with a fresh security-scoped one. If the refresh fails, the
    /// existing (stale but still resolvable) bookmark is kept instead of being dropped or
    /// downgraded to a bookmark without security scope.
    private func refreshStaleBookmark(for url: URL, pathKey: String) {
        guard let refreshedData = try? staleBookmarkRefresher(url) else {
            return
        }
        var bookmarks = recentFileBookmarks()
        bookmarks[pathKey] = refreshedData
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

    /// Creates a security-scoped bookmark for a URL resolved from a stale bookmark. Access to the
    /// security scope must be active while the new bookmark is created; there is deliberately no
    /// fallback to a non-scoped bookmark, which would lose sandbox access on the next launch.
    nonisolated static func makeRefreshedSecurityScopedBookmarkData(for url: URL) throws -> Data {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    nonisolated static func resolveBookmarkData(_ data: Data) throws -> BookmarkResolutionResult {
        var isStale = false
        // 最近文件菜单在主线程上构建：禁止解析过程弹出界面或挂载网络/外接卷，
        // 否则一个指向离线网络卷的条目就可能让菜单刷新长时间阻塞主线程。
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return BookmarkResolutionResult(url: url, isStale: isStale)
    }
}

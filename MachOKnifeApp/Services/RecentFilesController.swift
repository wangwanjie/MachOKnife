import Foundation
import MachOKnifeDB

final class RecentFilesController {
    private let settings: AppSettings
    private let database: AppDatabase

    init(settings: AppSettings = .shared, databaseURL: URL? = nil) throws {
        self.settings = settings

        let resolvedDatabaseURL = try databaseURL ?? Self.defaultDatabaseURL()
        try FileManager.default.createDirectory(
            at: resolvedDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.database = try AppDatabase(path: resolvedDatabaseURL.path)
    }

    func recordOpen(url: URL, openedAt: Date = Date()) throws {
        try makeStore().recordAccess(to: url, openedAt: openedAt)
    }

    func recentFileURLs() throws -> [URL] {
        try makeStore()
            .fetchRecentFiles()
            .prefix(settings.recentFilesLimit)
            .map { URL(fileURLWithPath: $0.path) }
    }

    private func makeStore() -> RecentFilesStore {
        RecentFilesStore(appDatabase: database, maxEntries: settings.recentFilesLimit)
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
}

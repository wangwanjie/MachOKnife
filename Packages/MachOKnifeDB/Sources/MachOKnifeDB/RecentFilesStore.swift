import Foundation
import GRDB

public struct RecentFilesStore {
    public static let defaultMaximumEntries = 50

    private let appDatabase: AppDatabase
    private let maxEntries: Int

    public init(appDatabase: AppDatabase, maxEntries: Int = RecentFilesStore.defaultMaximumEntries) {
        self.appDatabase = appDatabase
        self.maxEntries = maxEntries
    }

    public func recordAccess(to url: URL, openedAt: Date = Date()) throws {
        try appDatabase.dbQueue.write { db in
            try RecentFileRecord
                .filter(Column("path") == url.path)
                .deleteAll(db)

            try RecentFileRecord(path: url.path, openedAt: openedAt).insert(db)

            let rowsToDelete = try String.fetchAll(
                db,
                sql: """
                SELECT path
                FROM recentFiles
                ORDER BY openedAt DESC
                LIMIT -1 OFFSET ?
                """,
                arguments: [maxEntries]
            )

            if !rowsToDelete.isEmpty {
                try RecentFileRecord
                    .filter(rowsToDelete.contains(Column("path")))
                    .deleteAll(db)
            }
        }
    }

    public func fetchRecentFiles() throws -> [RecentFileRecord] {
        try appDatabase.dbQueue.read { db in
            try RecentFileRecord
                .order(Column("openedAt").desc)
                .fetchAll(db)
        }
    }

    static func makeForTesting(maxEntries: Int = RecentFilesStore.defaultMaximumEntries) throws -> RecentFilesStore {
        let queue = try DatabaseQueue()
        let database = try AppDatabase(dbQueue: queue)
        return RecentFilesStore(appDatabase: database, maxEntries: maxEntries)
    }
}

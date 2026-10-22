import Foundation
import GRDB

public struct RecentFilesStore {
    public static let defaultMaximumEntries = 50

    private let appDatabase: AppDatabase
    private let maxEntries: Int

    public init(appDatabase: AppDatabase, maxEntries: Int = RecentFilesStore.defaultMaximumEntries) {
        self.appDatabase = appDatabase
        // 负数上限没有意义：SQLite 会把负的 OFFSET 当作 0，结果与 0 相同（清空列表）。这里显式钳到 0，语义更清晰。
        self.maxEntries = max(0, maxEntries)
    }

    public func recordAccess(to url: URL, openedAt: Date = Date()) throws {
        try appDatabase.dbQueue.write { db in
            // 同一路径只保留一条：先删旧记录再插入，新记录会拿到更大的 rowid，用作同一时间戳下的先后顺序。
            try RecentFileRecord
                .filter(Column("path") == url.path)
                .deleteAll(db)

            try RecentFileRecord(path: url.path, openedAt: openedAt).insert(db)

            // 按与 fetchRecentFiles 完全相同的排序裁剪超出上限的旧记录，
            // 保证“被裁掉的”一定是列表末尾的那些（openedAt 相同的记录以前会被任意裁剪）。
            try db.execute(
                sql: """
                DELETE FROM recentFiles
                WHERE rowid IN (
                    SELECT rowid
                    FROM recentFiles
                    ORDER BY openedAt DESC, rowid DESC
                    LIMIT -1 OFFSET ?
                )
                """,
                arguments: [maxEntries]
            )
        }
    }

    public func fetchRecentFiles() throws -> [RecentFileRecord] {
        try appDatabase.dbQueue.read { db in
            // openedAt 只精确到毫秒，快速连续打开的文件可能时间戳相同；
            // 以 rowid 倒序作为次级排序，让后记录的文件稳定地排在前面。
            try RecentFileRecord
                .order(Column("openedAt").desc, Column.rowID.desc)
                .fetchAll(db)
        }
    }

    /// 删除全部最近文件记录（对应菜单中的“清除菜单”）。
    /// - Returns: 实际删除的记录条数。
    @discardableResult
    public func removeAll() throws -> Int {
        try appDatabase.dbQueue.write { db in
            try RecentFileRecord.deleteAll(db)
        }
    }

    static func makeForTesting(maxEntries: Int = RecentFilesStore.defaultMaximumEntries) throws -> RecentFilesStore {
        let queue = try DatabaseQueue()
        let database = try AppDatabase(dbQueue: queue)
        return RecentFilesStore(appDatabase: database, maxEntries: maxEntries)
    }
}

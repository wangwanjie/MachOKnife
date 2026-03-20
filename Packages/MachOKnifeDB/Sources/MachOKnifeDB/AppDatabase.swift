import Foundation
import GRDB

public struct AppDatabase {
    public let dbQueue: DatabaseQueue

    public init(path: String) throws {
        self.dbQueue = try DatabaseQueue(path: path)
        try Self.migrator.migrate(dbQueue)
    }

    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createRecentFiles") { db in
            try db.create(table: RecentFileRecord.databaseTableName) { table in
                table.column("path", .text).notNull().primaryKey()
                table.column("openedAt", .datetime).notNull()
            }
        }
        return migrator
    }
}

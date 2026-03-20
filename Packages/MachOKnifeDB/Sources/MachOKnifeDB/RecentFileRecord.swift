import Foundation
import GRDB

public struct RecentFileRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "recentFiles"

    public let path: String
    public let openedAt: Date

    public init(path: String, openedAt: Date) {
        self.path = path
        self.openedAt = openedAt
    }
}

import Foundation
import Testing
@testable import MachOKnifeDB

struct RecentFilesStoreTests {
    @Test("recent files are returned newest first")
    func recentFilesAreReturnedNewestFirst() throws {
        let store = try RecentFilesStore.makeForTesting(maxEntries: 50)

        try store.recordAccess(to: URL(filePath: "/tmp/one"), openedAt: Date(timeIntervalSince1970: 10))
        try store.recordAccess(to: URL(filePath: "/tmp/two"), openedAt: Date(timeIntervalSince1970: 20))

        let items = try store.fetchRecentFiles()

        #expect(items.map(\.path) == ["/tmp/two", "/tmp/one"])
    }

    @Test("duplicate paths are deduplicated and moved to the top")
    func duplicatePathsAreDeduplicatedAndMovedToTheTop() throws {
        let store = try RecentFilesStore.makeForTesting(maxEntries: 50)

        try store.recordAccess(to: URL(filePath: "/tmp/one"), openedAt: Date(timeIntervalSince1970: 10))
        try store.recordAccess(to: URL(filePath: "/tmp/two"), openedAt: Date(timeIntervalSince1970: 20))
        try store.recordAccess(to: URL(filePath: "/tmp/one"), openedAt: Date(timeIntervalSince1970: 30))

        let items = try store.fetchRecentFiles()

        #expect(items.map(\.path) == ["/tmp/one", "/tmp/two"])
    }

    @Test("default retention is fifty items")
    func defaultRetentionIsFiftyItems() throws {
        let store = try RecentFilesStore.makeForTesting()

        for index in 0..<55 {
            try store.recordAccess(
                to: URL(filePath: "/tmp/\(index)"),
                openedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let items = try store.fetchRecentFiles()

        #expect(items.count == 50)
        #expect(items.first?.path == "/tmp/54")
        #expect(items.last?.path == "/tmp/5")
    }

    @Test("custom retention trims older rows")
    func customRetentionTrimsOlderRows() throws {
        let store = try RecentFilesStore.makeForTesting(maxEntries: 3)

        for index in 0..<5 {
            try store.recordAccess(
                to: URL(filePath: "/tmp/\(index)"),
                openedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let items = try store.fetchRecentFiles()

        #expect(items.map(\.path) == ["/tmp/4", "/tmp/3", "/tmp/2"])
    }
}

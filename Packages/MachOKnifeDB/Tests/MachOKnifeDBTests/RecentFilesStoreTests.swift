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

    // 回归测试：openedAt 相同（毫秒精度内连续打开）时，后记录的文件必须排在前面，顺序不能随机。
    @Test("entries with identical timestamps are ordered by recording order")
    func identicalTimestampsAreOrderedByRecordingOrder() throws {
        let store = try RecentFilesStore.makeForTesting(maxEntries: 50)
        let sameMoment = Date(timeIntervalSince1970: 100)

        for name in ["a", "b", "c"] {
            try store.recordAccess(to: URL(filePath: "/tmp/\(name)"), openedAt: sameMoment)
        }
        // 重新打开 a：即使时间戳不变，也应移动到最前面。
        try store.recordAccess(to: URL(filePath: "/tmp/a"), openedAt: sameMoment)

        let items = try store.fetchRecentFiles()

        #expect(items.map(\.path) == ["/tmp/a", "/tmp/c", "/tmp/b"])
    }

    // 回归测试：裁剪必须与读取使用相同的排序，时间戳相同时保留最近记录的条目。
    @Test("retention keeps the most recently recorded entries when timestamps tie")
    func retentionKeepsMostRecentlyRecordedEntriesOnTimestampTies() throws {
        let store = try RecentFilesStore.makeForTesting(maxEntries: 2)
        let sameMoment = Date(timeIntervalSince1970: 100)

        for name in ["a", "b", "c", "d"] {
            try store.recordAccess(to: URL(filePath: "/tmp/\(name)"), openedAt: sameMoment)
        }

        let items = try store.fetchRecentFiles()

        #expect(items.map(\.path) == ["/tmp/d", "/tmp/c"])
    }

    @Test("a non-positive retention keeps no entries")
    func nonPositiveRetentionKeepsNoEntries() throws {
        for limit in [0, -5] {
            let store = try RecentFilesStore.makeForTesting(maxEntries: limit)

            try store.recordAccess(to: URL(filePath: "/tmp/one"), openedAt: Date(timeIntervalSince1970: 10))

            #expect(try store.fetchRecentFiles().isEmpty)
        }
    }

    @Test("an older openedAt for a re-opened path replaces the previous timestamp")
    func reopeningWithOlderTimestampReplacesPreviousRecord() throws {
        let store = try RecentFilesStore.makeForTesting(maxEntries: 50)

        try store.recordAccess(to: URL(filePath: "/tmp/one"), openedAt: Date(timeIntervalSince1970: 30))
        try store.recordAccess(to: URL(filePath: "/tmp/two"), openedAt: Date(timeIntervalSince1970: 20))
        try store.recordAccess(to: URL(filePath: "/tmp/one"), openedAt: Date(timeIntervalSince1970: 10))

        let items = try store.fetchRecentFiles()

        // 每个路径只保留一条记录，且使用最新一次记录的时间戳。
        #expect(items.map(\.path) == ["/tmp/two", "/tmp/one"])
        #expect(items.last?.openedAt == Date(timeIntervalSince1970: 10))
    }

    @Test("records persist across database reopen and migrations are idempotent")
    func recordsPersistAcrossReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MachOKnifeDBTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let databasePath = directory.appendingPathComponent("recent.sqlite").path

        do {
            let store = RecentFilesStore(appDatabase: try AppDatabase(path: databasePath))
            try store.recordAccess(to: URL(filePath: "/tmp/persisted"), openedAt: Date(timeIntervalSince1970: 42))
        }

        // 第二次打开同一个数据库文件会再次执行迁移器，已应用的迁移不能重复执行或报错。
        let reopened = RecentFilesStore(appDatabase: try AppDatabase(path: databasePath))
        let items = try reopened.fetchRecentFiles()

        #expect(items.map(\.path) == ["/tmp/persisted"])
        #expect(items.first?.openedAt == Date(timeIntervalSince1970: 42))
    }

    @Test("concurrent recording from many threads keeps one row per path")
    func concurrentRecordingIsSerialized() throws {
        let store = try RecentFilesStore.makeForTesting(maxEntries: 50)
        let failures = FailureCounter()

        // DatabaseQueue 串行化所有写入；并发调用不应报错，也不应产生重复路径。
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            do {
                try store.recordAccess(
                    to: URL(filePath: "/tmp/\(index % 10)"),
                    openedAt: Date(timeIntervalSince1970: TimeInterval(index))
                )
            } catch {
                failures.increment()
            }
        }

        let paths = try store.fetchRecentFiles().map(\.path)

        #expect(failures.value == 0)
        #expect(paths.count == 10)
        #expect(Set(paths).count == 10)
    }

    @Test("removeAll clears every recent file and reports how many were removed")
    func removeAllClearsEveryRecentFile() throws {
        let store = try RecentFilesStore.makeForTesting(maxEntries: 50)

        try store.recordAccess(to: URL(filePath: "/tmp/one"), openedAt: Date(timeIntervalSince1970: 10))
        try store.recordAccess(to: URL(filePath: "/tmp/two"), openedAt: Date(timeIntervalSince1970: 20))

        let removedCount = try store.removeAll()

        #expect(removedCount == 2)
        #expect(try store.fetchRecentFiles().isEmpty)
    }

    @Test("removeAll on an empty store is a no-op and recording works afterwards")
    func removeAllOnEmptyStoreIsNoOp() throws {
        let store = try RecentFilesStore.makeForTesting(maxEntries: 50)

        #expect(try store.removeAll() == 0)

        // 清空之后继续记录，列表应只包含新记录。
        try store.recordAccess(to: URL(filePath: "/tmp/after"), openedAt: Date(timeIntervalSince1970: 30))
        #expect(try store.fetchRecentFiles().map(\.path) == ["/tmp/after"])
    }
}

/// 线程安全的计数器，用于在并发测试中统计失败次数。
private final class FailureCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return count
    }
}

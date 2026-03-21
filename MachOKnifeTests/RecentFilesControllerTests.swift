import Foundation
import Testing
@testable import MachOKnife

struct RecentFilesControllerTests {
    @Test("records recent files in newest-first order and de-duplicates paths")
    func recordsRecentFilesInNewestFirstOrderAndDeDuplicatesPaths() throws {
        let settings = makeSettings()
        let controller = try makeController(settings: settings)
        let firstURL = try makeExistingFile(named: "A.dylib")
        let secondURL = try makeExistingFile(named: "B.dylib")

        try controller.recordOpen(url: firstURL, openedAt: Date(timeIntervalSince1970: 10))
        try controller.recordOpen(url: secondURL, openedAt: Date(timeIntervalSince1970: 20))
        try controller.recordOpen(url: firstURL, openedAt: Date(timeIntervalSince1970: 30))

        #expect(try controller.recentFileURLs() == [firstURL, secondURL])
    }

    @Test("uses the current settings limit when returning recent files")
    func usesTheCurrentSettingsLimitWhenReturningRecentFiles() throws {
        let settings = makeSettings()
        settings.recentFilesLimit = 2

        let controller = try makeController(settings: settings)
        let firstURL = try makeExistingFile(named: "1.dylib")
        let secondURL = try makeExistingFile(named: "2.dylib")
        let thirdURL = try makeExistingFile(named: "3.dylib")

        try controller.recordOpen(url: firstURL, openedAt: Date(timeIntervalSince1970: 10))
        try controller.recordOpen(url: secondURL, openedAt: Date(timeIntervalSince1970: 20))
        try controller.recordOpen(url: thirdURL, openedAt: Date(timeIntervalSince1970: 30))

        #expect(try controller.recentFileURLs() == [thirdURL, secondURL])

        settings.recentFilesLimit = 1
        #expect(try controller.recentFileURLs() == [thirdURL])
    }

    @Test("uses stored bookmarks when resolving recent file URLs after relaunch")
    func usesStoredBookmarksWhenResolvingRecentFileURLs() throws {
        let settings = makeSettings()
        let defaults = makeDefaults()
        let originalURL = try makeExistingFile(named: "Original.dylib")
        let resolvedURL = URL(filePath: "/tmp/MachOKnife/Resolved.dylib")
        let bookmarkData = Data("recent-bookmark".utf8)

        let controller = try makeController(
            settings: settings,
            defaults: defaults,
            bookmarkDataProvider: { url in
                #expect(url == originalURL)
                return bookmarkData
            },
            bookmarkResolver: { data in
                #expect(data == bookmarkData)
                return RecentFilesController.BookmarkResolutionResult(url: resolvedURL, isStale: false)
            }
        )

        try controller.recordOpen(url: originalURL, openedAt: Date(timeIntervalSince1970: 10))

        #expect(try controller.recentFileURLs() == [resolvedURL])
    }

    @Test("records recent files even when bookmark persistence fails")
    func recordsRecentFilesEvenWhenBookmarkPersistenceFails() throws {
        let settings = makeSettings()
        let controller = try makeController(
            settings: settings,
            bookmarkDataProvider: { _ in
                throw CocoaError(.fileNoSuchFile)
            }
        )
        let fileURL = try makeExistingFile(named: "BookmarkFallback.dylib")

        try controller.recordOpen(url: fileURL, openedAt: Date(timeIntervalSince1970: 10))

        #expect(try controller.recentFileURLs() == [fileURL])
    }

    private func makeController(
        settings: AppSettings,
        defaults: UserDefaults? = nil,
        bookmarkDataProvider: RecentFilesController.BookmarkDataProvider? = nil,
        bookmarkResolver: RecentFilesController.BookmarkResolver? = nil
    ) throws -> RecentFilesController {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("RecentFiles.sqlite")
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        return try RecentFilesController(
            settings: settings,
            databaseURL: databaseURL,
            defaults: defaults ?? makeDefaults(),
            bookmarkDataProvider: bookmarkDataProvider ?? RecentFilesController.makeBookmarkData(for:),
            bookmarkResolver: bookmarkResolver ?? RecentFilesController.resolveBookmarkData(_:)
        )
    }

    private func makeSettings(fileID: String = #fileID, line: Int = #line) -> AppSettings {
        let suiteName = "RecentFilesControllerTests.\(fileID).\(line).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults)
    }

    private func makeDefaults(fileID: String = #fileID, line: Int = #line) -> UserDefaults {
        let suiteName = "RecentFilesBookmarks.\(fileID).\(line).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeExistingFile(named name: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentFilesControllerTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent(name)
        try Data().write(to: fileURL)
        return fileURL
    }
}

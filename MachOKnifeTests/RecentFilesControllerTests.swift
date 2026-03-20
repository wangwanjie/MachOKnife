import Foundation
import Testing
@testable import MachOKnife

struct RecentFilesControllerTests {
    @Test("records recent files in newest-first order and de-duplicates paths")
    func recordsRecentFilesInNewestFirstOrderAndDeDuplicatesPaths() throws {
        let settings = makeSettings()
        let controller = try makeController(settings: settings)
        let firstURL = URL(filePath: "/tmp/MachOKnife/A.dylib")
        let secondURL = URL(filePath: "/tmp/MachOKnife/B.dylib")

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
        let firstURL = URL(filePath: "/tmp/MachOKnife/1.dylib")
        let secondURL = URL(filePath: "/tmp/MachOKnife/2.dylib")
        let thirdURL = URL(filePath: "/tmp/MachOKnife/3.dylib")

        try controller.recordOpen(url: firstURL, openedAt: Date(timeIntervalSince1970: 10))
        try controller.recordOpen(url: secondURL, openedAt: Date(timeIntervalSince1970: 20))
        try controller.recordOpen(url: thirdURL, openedAt: Date(timeIntervalSince1970: 30))

        #expect(try controller.recentFileURLs() == [thirdURL, secondURL])

        settings.recentFilesLimit = 1
        #expect(try controller.recentFileURLs() == [thirdURL])
    }

    private func makeController(settings: AppSettings) throws -> RecentFilesController {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("RecentFiles.sqlite")
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        return try RecentFilesController(settings: settings, databaseURL: databaseURL)
    }

    private func makeSettings(fileID: String = #fileID, line: Int = #line) -> AppSettings {
        let suiteName = "RecentFilesControllerTests.\(fileID).\(line).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults)
    }
}

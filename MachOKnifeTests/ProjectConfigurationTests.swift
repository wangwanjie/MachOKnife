import Foundation
import Testing

struct ProjectConfigurationTests {
    @Test("app target uses an explicit Info.plist with Sparkle metadata")
    func appTargetUsesExplicitInfoPlistWithSparkleMetadata() throws {
        let repositoryRoot = try repositoryRootURL()
        let infoPlistURL = repositoryRoot.appendingPathComponent("MachOKnife/Info.plist")
        #expect(FileManager.default.fileExists(atPath: infoPlistURL.path), "MachOKnife/Info.plist should exist")

        let plistData = try Data(contentsOf: infoPlistURL)
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
            "MachOKnife/Info.plist should decode as a property list dictionary"
        )

        #expect(plist["SUFeedURL"] as? String == "https://raw.githubusercontent.com/wangwanjie/MachOKnife/main/Resources/Updates/appcast.xml")
        #expect(plist["SUPublicEDKey"] as? String == "uC5c9/21BrXEuwkHiHoC0VbjetgST53JN+PW+y1BUt4=")
        #expect(plist["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(plist["SUAllowsAutomaticUpdates"] as? Bool == true)
        #expect(plist["MachOKnifeGitHubURL"] as? String == "https://github.com/wangwanjie/MachOKnife")

        let projectContents = try String(contentsOf: repositoryRoot.appendingPathComponent("MachOKnife.xcodeproj/project.pbxproj"))
        #expect(projectContents.contains("INFOPLIST_FILE = MachOKnife/Info.plist;"))
        #expect(projectContents.contains("GENERATE_INFOPLIST_FILE = NO;"))
    }

    @Test("app icon asset is fully wired to MachOKnife icon files")
    func appIconAssetIsFullyWiredToMachOKnifeIconFiles() throws {
        let repositoryRoot = try repositoryRootURL()
        let appIconURL = repositoryRoot
            .appendingPathComponent("MachOKnife")
            .appendingPathComponent("Assets.xcassets")
            .appendingPathComponent("AppIcon.appiconset")
        let contentsURL = appIconURL.appendingPathComponent("Contents.json")

        let data = try Data(contentsOf: contentsURL)
        let plist = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "AppIcon contents should decode as JSON"
        )
        let images = try XCTUnwrap(plist["images"] as? [[String: Any]], "AppIcon contents should contain image entries")

        #expect(images.isEmpty == false)
        for image in images {
            let filename = try XCTUnwrap(image["filename"] as? String, "Each app icon slot should have a filename")
            let fileURL = appIconURL.appendingPathComponent(filename)
            #expect(FileManager.default.fileExists(atPath: fileURL.path), "Missing app icon file \(filename)")
        }
    }

    private func repositoryRootURL(fileURL: URL = URL(filePath: #filePath)) throws -> URL {
        let testsDirectory = fileURL.deletingLastPathComponent()
        let repositoryRoot = testsDirectory.deletingLastPathComponent()

        guard FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent("MachOKnife.xcodeproj").path) else {
            throw ProjectConfigurationError.repositoryRootNotFound
        }

        return repositoryRoot
    }
}

private enum ProjectConfigurationError: Error {
    case repositoryRootNotFound
}

private func XCTUnwrap<T>(_ value: T?, _ message: @autoclosure () -> String = "") throws -> T {
    guard let value else {
        throw ProjectConfigurationTestFailure(message: message())
    }

    return value
}

private struct ProjectConfigurationTestFailure: Error {
    let message: String
}

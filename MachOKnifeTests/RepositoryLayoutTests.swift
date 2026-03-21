import Foundation
import Testing

struct RepositoryLayoutTests {
    @Test("milestone 1 repository layout exists")
    func milestoneOneRepositoryLayoutExists() throws {
        let repositoryRoot = try repositoryRootURL()
        let requiredPaths = [
            "MachOKnifeApp",
            "MachOKnifeCLI",
            "Packages",
            "Packages/CoreMachO/Package.swift",
            "Packages/RetagEngine/Package.swift",
            "Packages/MachOKnifeKit/Package.swift",
            "Packages/MachOKnifeDB/Package.swift",
            "Resources",
            "Resources/Updates/appcast.xml",
            "Scripts",
            "Scripts/common.sh",
            "Scripts/build_dmg.sh",
            "Scripts/generate_appcast.sh",
            "Scripts/publish_github_release.sh",
        ]

        for path in requiredPaths {
            let url = repositoryRoot.appendingPathComponent(path)
            #expect(FileManager.default.fileExists(atPath: url.path), "\(path) should exist in the repository layout")
        }
    }

    private func repositoryRootURL(fileURL: URL = URL(filePath: #filePath)) throws -> URL {
        let testsDirectory = fileURL.deletingLastPathComponent()
        let repositoryRoot = testsDirectory.deletingLastPathComponent()

        guard FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent("MachOKnife.xcodeproj").path) else {
            throw RepositoryLayoutError.repositoryRootNotFound
        }

        return repositoryRoot
    }
}

private enum RepositoryLayoutError: Error {
    case repositoryRootNotFound
}

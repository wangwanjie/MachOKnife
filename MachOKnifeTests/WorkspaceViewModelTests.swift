import Foundation
import CoreMachO
import MachOKnifeKit
import Testing
@testable import MachOKnife

@MainActor
struct WorkspaceViewModelTests {
    @Test("close document clears loaded state and returns workspace to empty state")
    func closeDocumentClearsLoadedState() throws {
        let fixtureURL = try makeEditableFixtureCopy()
        let viewModel = WorkspaceViewModel()

        #expect(viewModel.openDocument(at: fixtureURL))
        #expect(viewModel.hasLoadedDocument)
        #expect(viewModel.currentFileURL == fixtureURL)
        #expect(!viewModel.outlineItems.isEmpty)
        #expect(!viewModel.detailText.isEmpty)

        viewModel.closeCurrentDocument()

        #expect(viewModel.hasLoadedDocument == false)
        #expect(viewModel.currentFileURL == nil)
        #expect(viewModel.analysis == nil)
        #expect(viewModel.outlineItems.isEmpty)
        #expect(viewModel.selection == nil)
        #expect(viewModel.editableSlice == nil)
        #expect(viewModel.selectedSliceSummary == nil)
        #expect(viewModel.detailText.isEmpty)
        #expect(viewModel.inspectorText.isEmpty)
        #expect(viewModel.previewText.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("preview reflects install-name and rpath draft changes")
    func previewReflectsInstallNameAndRPathDraftChanges() throws {
        let fixtureURL = try makeEditableFixtureCopy()
        let viewModel = WorkspaceViewModel()

        #expect(viewModel.openDocument(at: fixtureURL))
        viewModel.setInstallNameDraft("@rpath/libWorkspacePreview.dylib")
        viewModel.replaceRPath(oldPath: "@loader_path/Frameworks", newPath: "@executable_path/Frameworks")

        try viewModel.previewEdits()

        #expect(viewModel.hasPendingEdits)
        #expect(viewModel.previewText.contains("@rpath/libWorkspacePreview.dylib"))
        #expect(viewModel.previewText.contains("@executable_path/Frameworks"))
    }

    @Test("save writes edited metadata to a new output file")
    func saveWritesEditedMetadataToANewOutputFile() throws {
        let fixtureURL = try makeEditableFixtureCopy()
        let outputURL = try makeTemporaryDirectory().appendingPathComponent("workspace-saved.dylib")
        let viewModel = WorkspaceViewModel()

        #expect(viewModel.openDocument(at: fixtureURL))
        viewModel.setInstallNameDraft("@rpath/libWorkspaceSaved.dylib")
        viewModel.replaceRPath(oldPath: "@loader_path/Frameworks", newPath: "@executable_path/Frameworks")

        let result = try viewModel.saveEdits(outputURL: outputURL, createBackup: false)
        let analysis = try DocumentAnalysisService().analyze(url: outputURL)

        #expect(result.outputURL == outputURL)
        #expect(analysis.slices.first?.installName == "@rpath/libWorkspaceSaved.dylib")
        #expect(analysis.slices.first?.rpaths.contains("@executable_path/Frameworks") == true)
    }

    @Test("preview reflects dylib-path and platform draft changes")
    func previewReflectsDylibPathAndPlatformDraftChanges() throws {
        let fixtureURL = try makeEditableFixtureCopy()
        let viewModel = WorkspaceViewModel()

        #expect(viewModel.openDocument(at: fixtureURL))
        viewModel.setDylibPathDraft(at: 0, newPath: "@loader_path/libCLIDependency.dylib")
        viewModel.setPlatformDraft(
            platform: .macCatalyst,
            minimumOS: MachOVersion(major: 17, minor: 0, patch: 0),
            sdk: MachOVersion(major: 17, minor: 4, patch: 0)
        )

        try viewModel.previewEdits()

        #expect(viewModel.hasPendingEdits)
        #expect(viewModel.previewText.contains("@loader_path/libCLIDependency.dylib"))
        #expect(viewModel.previewText.contains("macCatalyst"))
        #expect(viewModel.previewText.contains("17.4.0"))
    }

    @Test("save writes edited dylib-path and platform metadata")
    func saveWritesEditedDylibPathAndPlatformMetadata() throws {
        let fixtureURL = try makeEditableFixtureCopy()
        let outputURL = try makeTemporaryDirectory().appendingPathComponent("workspace-platform-saved.dylib")
        let viewModel = WorkspaceViewModel()

        #expect(viewModel.openDocument(at: fixtureURL))
        viewModel.setDylibPathDraft(at: 0, newPath: "@loader_path/libCLIDependency.dylib")
        viewModel.setPlatformDraft(
            platform: .macCatalyst,
            minimumOS: MachOVersion(major: 17, minor: 0, patch: 0),
            sdk: MachOVersion(major: 17, minor: 4, patch: 0)
        )

        let result = try viewModel.saveEdits(outputURL: outputURL, createBackup: false)
        let analysis = try DocumentAnalysisService().analyze(url: result.outputURL)

        #expect(analysis.slices.first?.dylibReferences.contains { $0.path == "@loader_path/libCLIDependency.dylib" } == true)
        #expect(analysis.slices.first?.platform == .macCatalyst)
        #expect(analysis.slices.first?.minimumOS == MachOVersion(major: 17, minor: 0, patch: 0))
        #expect(analysis.slices.first?.sdkVersion == MachOVersion(major: 17, minor: 4, patch: 0))
    }

    @Test("drafts persist when toggling between slice and document selections")
    func draftsPersistWhenTogglingBetweenSliceAndDocumentSelections() throws {
        let fixtureURL = try makeEditableFixtureCopy()
        let viewModel = WorkspaceViewModel()

        #expect(viewModel.openDocument(at: fixtureURL))
        viewModel.setInstallNameDraft("@rpath/libPersistentDraft.dylib")

        viewModel.select(.document)

        #expect(viewModel.editableSlice == nil)
        #expect(viewModel.hasPendingEdits == false)

        viewModel.select(.slice(0))

        #expect(viewModel.editableSlice?.installName == "@rpath/libPersistentDraft.dylib")
        #expect(viewModel.hasPendingEdits)
    }

    @Test("reanalyze preserves in-memory drafts for the active document session")
    func reanalyzePreservesInMemoryDraftsForTheActiveDocumentSession() throws {
        let fixtureURL = try makeEditableFixtureCopy()
        let viewModel = WorkspaceViewModel()

        #expect(viewModel.openDocument(at: fixtureURL))
        viewModel.setInstallNameDraft("@rpath/libReanalyzedDraft.dylib")

        viewModel.reanalyzeCurrentDocument()

        #expect(viewModel.editableSlice?.installName == "@rpath/libReanalyzedDraft.dylib")
        #expect(viewModel.hasPendingEdits)
    }

    @Test("save only rewrites the selected slice in a fat Mach-O")
    func saveOnlyRewritesTheSelectedSliceInAFatMachO() throws {
        let fixtureURL = try makeFatEditableFixture()
        let outputURL = try makeTemporaryDirectory().appendingPathComponent("fat-output.dylib")
        let viewModel = WorkspaceViewModel()

        #expect(viewModel.openDocument(at: fixtureURL))
        viewModel.select(.slice(0))
        viewModel.setInstallNameDraft("@rpath/libFatSlice0Only.dylib")

        let result = try viewModel.saveEdits(outputURL: outputURL, createBackup: false)
        let analysis = try DocumentAnalysisService().analyze(url: result.outputURL)

        #expect(analysis.slices.count == 2)
        #expect(analysis.slices[0].installName == "@rpath/libFatSlice0Only.dylib")
        #expect(analysis.slices[1].installName == "@rpath/libFatEditable.dylib")
    }

    @Test("outline exposes header, commands, segments, dylibs, rpaths, and symbols for each slice")
    func outlineExposesStructuredViewerSectionsForEachSlice() throws {
        let suiteName = "MachOKnifeTests.WorkspaceOutline.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        settings.language = .english

        let originalSettingsProvider = L10n.settingsProvider
        let originalBundleProvider = L10n.bundleProvider
        L10n.settingsProvider = { settings }
        L10n.bundleProvider = { .main }
        defer {
            L10n.settingsProvider = originalSettingsProvider
            L10n.bundleProvider = originalBundleProvider
            defaults.removePersistentDomain(forName: suiteName)
        }

        let fixtureURL = try makeEditableFixtureCopy()
        let viewModel = WorkspaceViewModel()

        #expect(viewModel.openDocument(at: fixtureURL))

        let documentItem = try #require(viewModel.outlineItems.first)
        let sliceItem = try #require(documentItem.children.first)
        let sectionTitles = sliceItem.children.map(\.title)

        #expect(sectionTitles.contains("Header"))
        #expect(sectionTitles.contains("Load Commands"))
        #expect(sectionTitles.contains("Segments"))
        #expect(sectionTitles.contains("Dynamic Libraries"))
        #expect(sectionTitles.contains("RPaths"))
        #expect(sectionTitles.contains("Symbols"))
    }

    private func makeEditableFixtureCopy() throws -> URL {
        let sourceURL = repoRoot()
            .appendingPathComponent("Resources")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("cli")
            .appendingPathComponent("libCLIEditable.dylib")
        let directory = try makeTemporaryDirectory()
        let destinationURL = directory.appendingPathComponent("libCLIEditable.dylib")
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func repoRoot() -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeFatEditableFixture() throws -> URL {
        let temporaryDirectory = try makeTemporaryDirectory()
        let sourceURL = temporaryDirectory.appendingPathComponent("fat-editable.c")
        let x86URL = temporaryDirectory.appendingPathComponent("libFatEditable-x86_64.dylib")
        let armURL = temporaryDirectory.appendingPathComponent("libFatEditable-arm64.dylib")
        let universalURL = temporaryDirectory.appendingPathComponent("libFatEditable.dylib")
        let source = "int fat_editable_fixture(void) { return 21; }\n"

        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

        try Shell.run(
            launchPath: DeveloperTool.path(named: "clang"),
            arguments: DeveloperTool.sdkArguments + [
                "-dynamiclib",
                "-target", "x86_64-apple-macos13.0",
                sourceURL.path,
                "-Wl,-install_name,@rpath/libFatEditable.dylib",
                "-o", x86URL.path,
            ]
        )
        try Shell.run(
            launchPath: DeveloperTool.path(named: "clang"),
            arguments: DeveloperTool.sdkArguments + [
                "-dynamiclib",
                "-target", "arm64-apple-macos13.0",
                sourceURL.path,
                "-Wl,-install_name,@rpath/libFatEditable.dylib",
                "-o", armURL.path,
            ]
        )
        try Shell.run(
            launchPath: DeveloperTool.path(named: "lipo"),
            arguments: [
                "-create",
                x86URL.path,
                armURL.path,
                "-output",
                universalURL.path,
            ]
        )

        return universalURL
    }
}

private enum Shell {
    static func run(launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ShellError.commandFailed(launchPath: launchPath, output: output)
        }
    }
}

private enum DeveloperTool {
    static func path(named tool: String) -> String {
        let fileManager = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
                .map { "\($0)/Toolchains/XcodeDefault.xctoolchain/usr/bin/\(tool)" },
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/\(tool)",
            "/Applications/XCode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/\(tool)",
            "/usr/bin/\(tool)",
        ].compactMap { $0 }

        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) ?? "/usr/bin/\(tool)"
    }

    static var sdkArguments: [String] {
        sdkRoot.map { ["-isysroot", $0] } ?? []
    }

    private static var sdkRoot: String? {
        let fileManager = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["SDKROOT"],
            ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
                .map { "\($0)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" },
            "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk",
            "/Applications/XCode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk",
        ].compactMap { $0 }

        return candidates.first(where: { fileManager.fileExists(atPath: $0) })
    }
}

private enum ShellError: Error {
    case commandFailed(launchPath: String, output: String)
}

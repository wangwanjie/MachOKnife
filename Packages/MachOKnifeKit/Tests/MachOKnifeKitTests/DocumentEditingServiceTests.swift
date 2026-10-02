import Foundation
import Testing
@testable import MachOKnifeKit
import CoreMachO

struct DocumentEditingServiceTests {
    @Test("preview surfaces diffs without mutating the source file")
    func previewSurfacesDiffsWithoutMutatingTheSourceFile() throws {
        let fixture = try EditingFixtureFactory.makeEditableFixture()
        let service = DocumentEditingService()

        let preview = try service.preview(
            inputURL: fixture.binaryURL,
            editPlan: MachOEditPlan(installName: "@rpath/libPreviewedFixture.dylib")
        )

        let original = try MachOContainer.parse(at: fixture.binaryURL)
        let originalSlice = try #require(original.slices.first)

        #expect(preview.diff.entries.contains(where: { $0.kind == .installName }))
        #expect(originalSlice.installName == "@rpath/libEditableFixture.dylib")
    }

    @Test("saving in place creates a .bak backup before overwriting")
    func savingInPlaceCreatesBackupBeforeOverwriting() throws {
        let fixture = try EditingFixtureFactory.makeEditableFixture()
        let service = DocumentEditingService()

        let result = try service.save(
            inputURL: fixture.binaryURL,
            editPlan: MachOEditPlan(installName: "@rpath/libInPlacePatched.dylib"),
            createBackup: true
        )

        let rewritten = try MachOContainer.parse(at: fixture.binaryURL)
        let backup = try MachOContainer.parse(at: result.backupURL!)

        #expect(FileManager.default.fileExists(atPath: result.backupURL!.path))
        #expect(rewritten.slices.first?.installName == "@rpath/libInPlacePatched.dylib")
        #expect(backup.slices.first?.installName == "@rpath/libEditableFixture.dylib")
    }

    @Test("saving to a new path leaves the source file untouched")
    func savingToNewPathLeavesTheSourceFileUntouched() throws {
        let fixture = try EditingFixtureFactory.makeEditableFixture()
        let outputURL = fixture.directory.appendingPathComponent("exported.dylib")
        let service = DocumentEditingService()

        let result = try service.save(
            inputURL: fixture.binaryURL,
            outputURL: outputURL,
            editPlan: MachOEditPlan(
                installName: "@rpath/libExportedFixture.dylib",
                rpathEdits: [.add("@loader_path")]
            ),
            createBackup: true
        )

        let source = try MachOContainer.parse(at: fixture.binaryURL)
        let exported = try MachOContainer.parse(at: outputURL)

        #expect(result.outputURL == outputURL)
        #expect(result.backupURL == nil)
        #expect(source.slices.first?.installName == "@rpath/libEditableFixture.dylib")
        #expect(exported.slices.first?.installName == "@rpath/libExportedFixture.dylib")
        #expect(exported.slices.first?.rpaths.contains("@loader_path") == true)
    }

    @Test("a failing in-place save leaves no temporary file, backup or modified input behind")
    func failingInPlaceSaveLeavesNothingBehind() throws {
        let fixture = try EditingFixtureFactory.makeEditableFixture()
        let originalData = try Data(contentsOf: fixture.binaryURL)
        let service = DocumentEditingService()

        #expect(throws: MachOWriteError.self) {
            try service.save(
                inputURL: fixture.binaryURL,
                editPlan: MachOEditPlan(installName: "@rpath/" + String(repeating: "x", count: 0x10000)),
                createBackup: true
            )
        }

        #expect(try Data(contentsOf: fixture.binaryURL) == originalData)
        #expect(try EditingFixtureFactory.temporaryFiles(in: fixture.directory).isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.binaryURL.appendingPathExtension("bak").path) == false)
    }

    @Test("a failing in-place replacement removes the temporary file")
    func failingInPlaceReplacementRemovesTemporaryFile() throws {
        let fixture = try EditingFixtureFactory.makeEditableFixture()
        let originalData = try Data(contentsOf: fixture.binaryURL)
        let service = DocumentEditingService(fileManager: FailingReplaceFileManager())

        #expect(throws: FailingReplaceFileManager.ReplaceError.self) {
            try service.save(
                inputURL: fixture.binaryURL,
                editPlan: MachOEditPlan(installName: "@rpath/libReplaceFails.dylib"),
                createBackup: false
            )
        }

        #expect(try Data(contentsOf: fixture.binaryURL) == originalData)
        #expect(try EditingFixtureFactory.temporaryFiles(in: fixture.directory).isEmpty)
    }
}

/// Simulates `replaceItemAt` failing after the edited temporary file was written.
private final class FailingReplaceFileManager: FileManager, @unchecked Sendable {
    struct ReplaceError: Error {}

    override func replaceItem(
        at originalItemURL: URL,
        withItemAt newItemURL: URL,
        backupItemName: String?,
        options: FileManager.ItemReplacementOptions = [],
        resultingItemURL: AutoreleasingUnsafeMutablePointer<NSURL?>?
    ) throws {
        throw ReplaceError()
    }
}

private struct EditingFixture {
    let directory: URL
    let binaryURL: URL
}

private enum EditingFixtureFactory {
    static func makeEditableFixture() throws -> EditingFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let sourceURL = directory.appendingPathComponent("fixture.c")
        let binaryURL = directory.appendingPathComponent("libEditableFixture.dylib")
        try "int editable_fixture(void) { return 11; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/clang")
        process.arguments = [
            "-target", "x86_64-apple-macos13.0",
            "-dynamiclib",
            sourceURL.path,
            "-Wl,-headerpad,0x4000",
            "-Wl,-install_name,@rpath/libEditableFixture.dylib",
            "-o",
            binaryURL.path,
        ]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw EditingFixtureError.compileFailed
        }

        return EditingFixture(directory: directory, binaryURL: binaryURL)
    }
}

extension EditingFixtureFactory {
    static func temporaryFiles(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".tmp") }
    }
}

private enum EditingFixtureError: Error {
    case compileFailed
}

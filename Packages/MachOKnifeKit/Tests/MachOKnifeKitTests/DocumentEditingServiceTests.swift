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

private enum EditingFixtureError: Error {
    case compileFailed
}

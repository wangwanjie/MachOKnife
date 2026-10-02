import CoreMachO
import Foundation

public struct DocumentEditingService {
    private let writer = MachOWriter()
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func preview(inputURL: URL, editPlan: MachOEditPlan) throws -> DocumentEditPreview {
        let diff = try writer.preview(inputURL: inputURL, editPlan: editPlan)
        return DocumentEditPreview(inputURL: inputURL, diff: diff)
    }

    public func save(
        inputURL: URL,
        outputURL: URL? = nil,
        editPlan: MachOEditPlan,
        createBackup: Bool = true
    ) throws -> DocumentSaveResult {
        let destinationURL = outputURL ?? inputURL

        if destinationURL.standardizedFileURL == inputURL.standardizedFileURL {
            return try saveInPlace(inputURL: inputURL, editPlan: editPlan, createBackup: createBackup)
        }

        let writeResult = try writer.write(inputURL: inputURL, outputURL: destinationURL, editPlan: editPlan)
        return DocumentSaveResult(outputURL: destinationURL, backupURL: nil, diff: writeResult.diff)
    }

    private func saveInPlace(inputURL: URL, editPlan: MachOEditPlan, createBackup: Bool) throws -> DocumentSaveResult {
        let temporaryURL = inputURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp")
        let backupURL = createBackup ? inputURL.appendingPathExtension("bak") : nil

        // The temporary file must never outlive this call: remove it whenever the write, the
        // backup or the replacement fails. After a successful replacement it no longer exists.
        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        // Write first so a failing edit neither touches the input nor replaces an existing backup.
        let writeResult = try writer.write(inputURL: inputURL, outputURL: temporaryURL, editPlan: editPlan)

        if let backupURL {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: inputURL, to: backupURL)
        }

        _ = try fileManager.replaceItemAt(inputURL, withItemAt: temporaryURL)

        return DocumentSaveResult(outputURL: inputURL, backupURL: backupURL, diff: writeResult.diff)
    }
}

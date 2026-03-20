import AppKit

enum WindowSnapshotError: LocalizedError {
    case missingWindow
    case missingSnapshotView
    case bitmapCreationFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .missingWindow:
            return "The window was not available for snapshotting."
        case .missingSnapshotView:
            return "The snapshot source view was not available."
        case .bitmapCreationFailed:
            return "The window snapshot bitmap could not be created."
        case .pngEncodingFailed:
            return "The window snapshot could not be encoded as PNG."
        }
    }
}

enum WindowSnapshot {
    static func writePNG(for window: NSWindow?, to url: URL) throws {
        guard let window else {
            throw WindowSnapshotError.missingWindow
        }
        guard let snapshotView = window.contentView?.superview ?? window.contentView else {
            throw WindowSnapshotError.missingSnapshotView
        }

        snapshotView.layoutSubtreeIfNeeded()
        snapshotView.displayIfNeeded()

        let bounds = snapshotView.bounds.integral
        guard let bitmap = snapshotView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw WindowSnapshotError.bitmapCreationFailed
        }
        bitmap.size = bounds.size
        snapshotView.cacheDisplay(in: bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw WindowSnapshotError.pngEncodingFailed
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }
}

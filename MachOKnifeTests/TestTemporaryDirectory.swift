import Foundation

extension FileManager {
    /// The temporary directory with symlinks resolved (`/var` → `/private/var`), matching the
    /// paths that security-scoped bookmarks resolve to. `resolvingSymlinksInPath()` cannot be used
    /// here because it deliberately maps `/private/var` back to `/var`.
    var canonicalTemporaryDirectory: URL {
        guard let resolved = realpath(temporaryDirectory.path, nil) else { return temporaryDirectory }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }
}

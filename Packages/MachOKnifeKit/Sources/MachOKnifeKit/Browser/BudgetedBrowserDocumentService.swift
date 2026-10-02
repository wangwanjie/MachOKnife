import CoreMachO
import Foundation

public extension BrowserDocumentService {
    /// The layout engine builds every heavy group (symbols, strings, relocations, ...) lazily, so large
    /// files use the same loader; `scan` is kept for API compatibility with the staged workspace loader.
    func loadBudgeted(url: URL, scan: MachOMetadataScan) throws -> BrowserDocument {
        try load(url: url)
    }
}

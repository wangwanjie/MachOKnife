import Foundation

public enum MachOMetadataScanner {
    public static func scan(at url: URL) throws -> MachOMetadataScan {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let parser = MachOFileParser(data: data)
        return try parser.parseMetadataScan(fileURL: url, fileSize: data.count)
    }
}

public enum MachOSymbolTableReaderError: Error {
    case missingSymbolTable
    case invalidMaximumCount(Int)
    case startIndexOutOfBounds(startIndex: Int, totalSymbolCount: Int)
}

public struct MachOSymbolTablePage: Sendable {
    public let startIndex: Int
    public let symbols: [SymbolInfo]
    public let totalSymbolCount: Int

    public init(startIndex: Int, symbols: [SymbolInfo], totalSymbolCount: Int) {
        self.startIndex = startIndex
        self.symbols = symbols
        self.totalSymbolCount = totalSymbolCount
    }
}

public struct MachOSymbolTablePageReader: Sendable {
    public init() {}

    public func readPage(
        url: URL,
        slice: MachOMetadataSlice,
        startIndex: Int,
        maximumCount: Int
    ) throws -> MachOSymbolTablePage {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let parser = MachOFileParser(data: data)
        return try parser.readSymbolPage(slice: slice, startIndex: startIndex, maximumCount: maximumCount)
    }
}

public enum MachOStringTableReaderError: Error {
    case missingSymbolTable
    case invalidMaximumCount(Int)
    case startIndexOutOfBounds(startIndex: Int, totalEntryCount: Int)
}

public struct MachOStringTableEntry: Sendable {
    public let stringTableIndex: Int
    public let string: String

    public init(stringTableIndex: Int, string: String) {
        self.stringTableIndex = stringTableIndex
        self.string = string
    }
}

public struct MachOStringTableBatch: Sendable {
    public let startIndex: Int
    public let entries: [MachOStringTableEntry]
    public let totalEntryCount: Int
    public let totalStringTableSize: Int

    public init(
        startIndex: Int,
        entries: [MachOStringTableEntry],
        totalEntryCount: Int,
        totalStringTableSize: Int
    ) {
        self.startIndex = startIndex
        self.entries = entries
        self.totalEntryCount = totalEntryCount
        self.totalStringTableSize = totalStringTableSize
    }
}

public struct MachOStringTableBatchReader: Sendable {
    public init() {}

    public func readBatch(
        url: URL,
        slice: MachOMetadataSlice,
        startIndex: Int,
        maximumCount: Int
    ) throws -> MachOStringTableBatch {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let parser = MachOFileParser(data: data)
        return try parser.readStringTableBatch(slice: slice, startIndex: startIndex, maximumCount: maximumCount)
    }
}

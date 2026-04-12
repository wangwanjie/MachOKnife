import Foundation
import Testing
@testable import CoreMachO

struct MachOMetadataScanTests {
    @Test("scans first-paint metadata without eagerly decoding symbol records")
    func scansFirstPaintMetadataWithoutEagerSymbolRecords() throws {
        let fixture = try ScanFixtureFactory.makeDynamicLibraryFixture(symbolCount: 32)

        let scan = try MachOMetadataScanner.scan(at: fixture.binaryURL)
        let slice = try #require(scan.slices.first)

        #expect(scan.fileURL == fixture.binaryURL)
        #expect(scan.fileSize > 0)
        #expect(slice.installName == "@rpath/libScanFixture.dylib")
        #expect(slice.loadCommands.isEmpty == false)
        #expect(slice.segments.isEmpty == false)
        #expect(slice.dylibReferences.isEmpty == false)
        #expect(slice.rpathCommands.contains(where: { $0.path == "@loader_path/Frameworks" }))
        #expect(slice.symbolTable?.symbolCount ?? 0 > 0)
        #expect(slice.heavyCollectionEstimate.symbolCount == Int(slice.symbolTable?.symbolCount ?? 0))
        #expect(slice.heavyCollectionEstimate.stringTableSize == Int(slice.symbolTable?.stringTableSize ?? 0))
        #expect(slice.heavyCollectionEstimate.estimatedNodeCount > slice.loadCommands.count)
    }

    @Test("reads bounded symbol pages and rejects out-of-range requests")
    func readsBoundedSymbolPagesAndRejectsOutOfRangeRequests() throws {
        let fixture = try ScanFixtureFactory.makeObjectFixture(symbolCount: 24)
        let scan = try MachOMetadataScanner.scan(at: fixture.binaryURL)
        let slice = try #require(scan.slices.first)
        let reader = MachOSymbolTablePageReader()

        let page = try reader.readPage(
            url: fixture.binaryURL,
            slice: slice,
            startIndex: 2,
            maximumCount: 5
        )

        #expect(page.startIndex == 2)
        #expect(page.symbols.count == 5)
        #expect(page.totalSymbolCount >= page.startIndex + page.symbols.count)
        #expect(page.symbols.contains(where: { $0.name.contains("scan_fixture_symbol_") }))

        do {
            _ = try reader.readPage(
                url: fixture.binaryURL,
                slice: slice,
                startIndex: page.totalSymbolCount,
                maximumCount: 1
            )
            Issue.record("Expected an out-of-range symbol page read to throw.")
        } catch let error as MachOSymbolTableReaderError {
            guard case .startIndexOutOfBounds(let startIndex, let totalSymbolCount) = error else {
                Issue.record("Unexpected symbol page error: \(error)")
                return
            }

            #expect(startIndex == page.totalSymbolCount)
            #expect(totalSymbolCount == page.totalSymbolCount)
        }
    }

    @Test("reads bounded string-table batches and rejects out-of-range requests")
    func readsBoundedStringTableBatchesAndRejectsOutOfRangeRequests() throws {
        let fixture = try ScanFixtureFactory.makeObjectFixture(symbolCount: 24)
        let scan = try MachOMetadataScanner.scan(at: fixture.binaryURL)
        let slice = try #require(scan.slices.first)
        let reader = MachOStringTableBatchReader()

        let batch = try reader.readBatch(
            url: fixture.binaryURL,
            slice: slice,
            startIndex: 0,
            maximumCount: 32
        )

        #expect(batch.startIndex == 0)
        #expect(batch.entries.isEmpty == false)
        #expect(batch.totalStringTableSize == Int(slice.symbolTable?.stringTableSize ?? 0))
        #expect(batch.entries.contains(where: { $0.string.contains("scan_fixture_symbol_") }))

        do {
            _ = try reader.readBatch(
                url: fixture.binaryURL,
                slice: slice,
                startIndex: 10_000,
                maximumCount: 1
            )
            Issue.record("Expected an out-of-range string-table batch read to throw.")
        } catch let error as MachOStringTableReaderError {
            guard case .startIndexOutOfBounds(let startIndex, let totalEntryCount) = error else {
                Issue.record("Unexpected string-table reader error: \(error)")
                return
            }

            #expect(startIndex == 10_000)
            #expect(totalEntryCount > 0)
        }
    }
}

private struct ScanFixture {
    let directory: URL
    let binaryURL: URL
}

private enum ScanFixtureFactory {
    static func makeDynamicLibraryFixture(symbolCount: Int) throws -> ScanFixture {
        let directory = try makeFixtureDirectory()
        let sourceURL = directory.appendingPathComponent("scan-fixture.c")
        let binaryURL = directory.appendingPathComponent("libScanFixture.dylib")

        try source(forSymbolCount: symbolCount).write(to: sourceURL, atomically: true, encoding: .utf8)
        try ScanFixtureCommand.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-macos13.0",
                "-dynamiclib",
                sourceURL.path,
                "-Wl,-headerpad,0x4000",
                "-Wl,-install_name,@rpath/libScanFixture.dylib",
                "-Wl,-rpath,@loader_path/Frameworks",
                "-o",
                binaryURL.path,
            ]
        )

        return ScanFixture(directory: directory, binaryURL: binaryURL)
    }

    static func makeObjectFixture(symbolCount: Int) throws -> ScanFixture {
        let directory = try makeFixtureDirectory()
        let sourceURL = directory.appendingPathComponent("scan-fixture.c")
        let binaryURL = directory.appendingPathComponent("scan-fixture.o")

        try source(forSymbolCount: symbolCount).write(to: sourceURL, atomically: true, encoding: .utf8)
        try ScanFixtureCommand.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-macos13.0",
                "-c",
                sourceURL.path,
                "-o",
                binaryURL.path,
            ]
        )

        return ScanFixture(directory: directory, binaryURL: binaryURL)
    }

    private static func makeFixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func source(forSymbolCount symbolCount: Int) -> String {
        let functionDefinitions = (0..<symbolCount).map { index in
            "int scan_fixture_symbol_\(index)(void) { return \(index); }"
        }
        let aggregateBody = (0..<symbolCount).map { "value += scan_fixture_symbol_\($0)();" }.joined(separator: "\n    ")

        return """
        \(functionDefinitions.joined(separator: "\n"))
        int scan_fixture_sum(void) {
            int value = 0;
            \(aggregateBody)
            return value;
        }
        """
    }
}

private enum ScanFixtureCommand {
    static func run(launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let combinedOutput = String(data: outputData + errorData, encoding: .utf8) ?? "unknown error"
            throw ScanFixtureError.commandFailed("\(launchPath) \(arguments.joined(separator: " "))\n\(combinedOutput)")
        }
    }
}

private enum ScanFixtureError: Error {
    case commandFailed(String)
}

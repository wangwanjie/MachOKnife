import Foundation
import Testing
@testable import MachOKnifeKit

struct BrowserDocumentServiceTests {
    @Test("loads a Mach-O fixture with explicit browser categories for advanced metadata")
    func loadsMachOFixtureWithExplicitBrowserCategories() throws {
        let fixtureURL = try BrowserFixtureFactory.makeThinFixture()
        let service = BrowserDocumentService()

        let document = try service.load(url: fixtureURL)

        #expect(document.kind == .machOFile)

        let rootNode = try #require(document.rootNodes.first)
        let categoryTitles = Set(rootNode.children.map(\.title))

        #expect(categoryTitles.contains("Header"))
        #expect(categoryTitles.contains(where: { $0.hasPrefix("Load Commands") }))
        #expect(categoryTitles.contains("Segments"))
        #expect(categoryTitles.contains("Sections"))
        #expect(categoryTitles.contains("Symbols"))
        #expect(categoryTitles.contains("String Tables"))
        #expect(categoryTitles.contains("Bindings"))
        #expect(categoryTitles.contains("Exports"))
        #expect(categoryTitles.contains("Fixups"))
        #expect(categoryTitles.contains("Function Starts"))
        #expect(categoryTitles.contains("Data In Code"))
        #expect(categoryTitles.contains("Code Sign"))
        #expect(categoryTitles.contains("Raw Object"))
    }

    @Test("loads an in-memory Mach-O image with browser metadata and no hex source")
    func loadsMemoryImage() throws {
        let service = BrowserDocumentService()

        let document = try service.loadMemoryImage(named: "Foundation")

        #expect(document.kind == .memoryImage)
        #expect(document.rootNodes.isEmpty == false)
        #expect(document.sourceName == "Foundation")

        guard case let .unavailable(reason) = document.hexSource else {
            Issue.record("Expected memory-image hex source to be unavailable in this pass.")
            return
        }

        #expect(reason.contains("memory images"))
    }

    @Test("header detail rows use semantic names for magic and CPU type")
    func headerDetailRowsUseSemanticNames() throws {
        let fixtureURL = try BrowserFixtureFactory.makeThinFixture()
        let service = BrowserDocumentService()

        let document = try service.load(url: fixtureURL)
        let rootNode = try #require(document.rootNodes.first)
        let headerNode = try #require(rootNode.children.first(where: { $0.title == "Header" }))

        let magicRow = try #require(headerNode.detailRows.first(where: { $0.key == "Magic" }))
        let cpuTypeRow = try #require(headerNode.detailRows.first(where: { $0.key == "CPU Type" }))

        #expect(magicRow.value.contains("MH_MAGIC"))
        #expect(cpuTypeRow.value.contains("CPU_TYPE"))
    }

    @Test("root node exposes semantic Mach-O summary")
    func rootNodeExposesSemanticSummary() throws {
        let fixtureURL = try BrowserFixtureFactory.makeThinFixture()
        let service = BrowserDocumentService()

        let document = try service.load(url: fixtureURL)
        let rootNode = try #require(document.rootNodes.first)

        let subtitle = try #require(rootNode.subtitle)
        #expect(subtitle.contains("MH_MAGIC"))
        #expect(subtitle.contains("CPU_TYPE_X86_64"))
        #expect(subtitle.contains("MH_OBJECT"))

        let magicRow = try #require(rootNode.detailRows.first(where: { $0.key == "Magic" }))
        let fileTypeRow = try #require(rootNode.detailRows.first(where: { $0.key == "File Type" }))

        #expect(magicRow.value.contains("MH_MAGIC"))
        #expect(fileTypeRow.value.contains("MH_OBJECT"))
    }

    @Test("objective-c class list lazily exposes class names")
    func objectiveCClassListLazilyExposesClassNames() throws {
        let fixtureURL = try BrowserFixtureFactory.makeObjCFixture()
        let service = BrowserDocumentService()

        let document = try service.load(url: fixtureURL)
        let rootNode = try #require(document.rootNodes.first)
        let sectionsNode = try #require(rootNode.children.first(where: { $0.title == "Sections" }))
        let classListNode = try #require(sectionsNode.children.first(where: { $0.title.contains("__objc_classlist") }))

        #expect(classListNode.childCount == 1)
        #expect(classListNode.loadedChildren.isEmpty)
        #expect(classListNode.title.contains("(1)"))

        let classNode = classListNode.child(at: 0)
        #expect(classNode.title == "BrowserFixtureClass")
        #expect(classListNode.loadedChildren.count == 1)
    }

    @Test("objective-c category and method-name sections expose symbolic children")
    func objectiveCCategoryAndMethodNameSectionsExposeSymbolicChildren() throws {
        let fixtureURL = try BrowserFixtureFactory.makeObjCCategoryFixture()
        let service = BrowserDocumentService()

        let document = try service.load(url: fixtureURL)
        let rootNode = try #require(document.rootNodes.first)
        let sectionsNode = try #require(rootNode.children.first(where: { $0.title == "Sections" }))

        let categoryListNode = try #require(sectionsNode.children.first(where: { $0.title.contains("__objc_catlist") }))
        let methodNameNode = try #require(sectionsNode.children.first(where: { $0.title.contains("__objc_methname") }))

        #expect(categoryListNode.childCount == 1)
        #expect(categoryListNode.child(at: 0).title.contains("BrowserFixtureClass"))
        #expect(categoryListNode.child(at: 0).title.contains("Extra"))

        let methodTitles = methodNameNode.children.map(\.title)
        #expect(methodTitles.contains("baseMethod"))
        #expect(methodTitles.contains("categoryMethod"))
    }

    @Test("group nodes expose child summaries instead of leaking first descendant values")
    func groupNodesExposeChildSummaries() throws {
        let fixtureURL = try BrowserFixtureFactory.makeThinFixture()
        let service = BrowserDocumentService()

        let document = try service.load(url: fixtureURL)
        let rootNode = try #require(document.rootNodes.first)
        let stringTablesNode = try #require(rootNode.children.first(where: { $0.title == "String Tables" }))
        let cStringsRow = try #require(stringTablesNode.detailRows.first(where: { $0.key == "C Strings" }))

        #expect(cStringsRow.value != "C Strings")
        #expect(cStringsRow.value.contains("item"))
    }

    @Test("leaf summaries keep semantic field names in Description and values in Value")
    func leafSummariesKeepSemanticFieldNames() throws {
        let fixtureURL = try BrowserFixtureFactory.makeExecutableFixture()
        let service = BrowserDocumentService()

        let document = try service.load(url: fixtureURL)
        let rootNode = try #require(document.rootNodes.first)
        let symbolsNode = try #require(rootNode.children.first(where: { $0.title == "Symbols" }))
        let symbolRow = try #require(symbolsNode.detailRows.first)

        #expect(symbolRow.key == "Name")
        #expect(symbolRow.value.isEmpty == false)
    }

    @Test("load command nodes expose command lists and layout details")
    func loadCommandNodesExposeCommandListsAndLayoutDetails() throws {
        let fixtureURL = try BrowserFixtureFactory.makeExecutableFixture()
        let service = BrowserDocumentService()

        let document = try service.load(url: fixtureURL)
        let rootNode = try #require(document.rootNodes.first)
        let loadCommandsNode = try #require(rootNode.children.first(where: { $0.title.hasPrefix("Load Commands") }))

        #expect(loadCommandsNode.detailCount == loadCommandsNode.childCount)
        #expect(loadCommandsNode.title.contains("(\(loadCommandsNode.childCount))"))

        let commandNode = loadCommandsNode.child(at: 0)
        #expect(commandNode.title.hasPrefix("0.") == false)
        #expect(commandNode.detailRows.contains(where: { $0.key == "Load Command" }))
        #expect(commandNode.detailRows.contains(where: { $0.key == "Command Size" }))

        let dylibNode = try #require(loadCommandsNode.children.first(where: { node in
            node.detailRows.contains(where: { $0.key == "Library" })
        }))
        let libraryRow = try #require(dylibNode.detailRows.first(where: { $0.key == "Library" }))

        #expect(libraryRow.value.contains("/"))
        #expect(dylibNode.title.contains((libraryRow.value as NSString).lastPathComponent))
        #expect(dylibNode.title.contains(libraryRow.value) == false)
    }

    @Test("objective-c special sections use type labels in Description and names in Value")
    func objectiveCSpecialSectionsUseTypeLabelsInDescription() throws {
        let fixtureURL = try BrowserFixtureFactory.makeObjCCategoryFixture()
        let service = BrowserDocumentService()

        let document = try service.load(url: fixtureURL)
        let rootNode = try #require(document.rootNodes.first)
        let sectionsNode = try #require(rootNode.children.first(where: { $0.title == "Sections" }))
        let categoryListNode = try #require(sectionsNode.children.first(where: { $0.title.contains("__objc_catlist") }))

        let summaryRow = try #require(categoryListNode.detailRows.first(where: { $0.key == "Objective-C Category" }))
        #expect(summaryRow.key == "Objective-C Category")
        #expect(summaryRow.value.contains("BrowserFixtureClass"))
    }
}

private enum BrowserFixtureFactory {
    static func makeThinFixture() throws -> URL {
        let source = """
        const char *machoknife_browser_fixture(void) { return "MachOKnife"; }
        """
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let sourceURL = tempDirectory.appendingPathComponent("browser-fixture.c")
        let outputURL = tempDirectory.appendingPathComponent("browser-fixture.o")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/clang")
        process.arguments = [
            "-target", "x86_64-apple-macos13.0",
            "-c",
            sourceURL.path,
            "-o",
            outputURL.path,
        ]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw BrowserFixtureError.compileFailed
        }

        return outputURL
    }

    static func makeObjCFixture() throws -> URL {
        let source = """
        #import <objc/NSObject.h>
        @interface BrowserFixtureClass : NSObject
        @end
        @implementation BrowserFixtureClass
        @end
        """
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let sourceURL = tempDirectory.appendingPathComponent("browser-fixture.m")
        let outputURL = tempDirectory.appendingPathComponent("browser-fixture.o")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/clang")
        process.arguments = [
            "-target", "x86_64-apple-macos13.0",
            "-c",
            sourceURL.path,
            "-o",
            outputURL.path,
        ]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw BrowserFixtureError.compileFailed
        }

        return outputURL
    }

    static func makeObjCCategoryFixture() throws -> URL {
        let source = """
        #import <objc/NSObject.h>
        @interface BrowserFixtureClass : NSObject
        - (void)baseMethod;
        @end
        @implementation BrowserFixtureClass
        - (void)baseMethod {}
        @end
        @interface BrowserFixtureClass (Extra)
        - (void)categoryMethod;
        @end
        @implementation BrowserFixtureClass (Extra)
        - (void)categoryMethod {}
        @end
        """
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let sourceURL = tempDirectory.appendingPathComponent("browser-category-fixture.m")
        let outputURL = tempDirectory.appendingPathComponent("browser-category-fixture.o")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/clang")
        process.arguments = [
            "-target", "x86_64-apple-macos13.0",
            "-c",
            sourceURL.path,
            "-o",
            outputURL.path,
        ]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw BrowserFixtureError.compileFailed
        }

        return outputURL
    }

    static func makeExecutableFixture() throws -> URL {
        let source = """
        int exported_value(void) { return 42; }
        int main(void) { return exported_value(); }
        """
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let sourceURL = tempDirectory.appendingPathComponent("browser-executable-fixture.c")
        let outputURL = tempDirectory.appendingPathComponent("browser-executable-fixture")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/clang")
        process.arguments = [
            "-target", "x86_64-apple-macos13.0",
            sourceURL.path,
            "-o",
            outputURL.path,
        ]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw BrowserFixtureError.compileFailed
        }

        return outputURL
    }
}

private enum BrowserFixtureError: Error {
    case compileFailed
}

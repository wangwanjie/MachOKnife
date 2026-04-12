import CoreMachO
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

    @Test("archive documents expose a container root, target nodes, and file-backed hex data")
    func archiveDocumentsExposeContainerRootTargetNodesAndHexData() throws {
        let fixtureURL = try BrowserFixtureFactory.makeFatArchiveFixture()
        let service = BrowserDocumentService()

        let document = try service.load(url: fixtureURL)

        #expect(document.kind == .archive)
        #expect(document.rootNodes.count == 1)
        let rootNode = try #require(document.rootNodes.first)
        #expect(rootNode.title == "Fat Archive")
        #expect(rootNode.childCount == 2)

        let targetTitles = Set(rootNode.children.map(\.title))
        #expect(targetTitles.contains("Static Library (iphoneos_ARM64)"))
        #expect(targetTitles.contains("Static Library (iphonesimulator_X86_64)"))

        let arm64TargetNode = try #require(rootNode.children.first(where: { $0.title == "Static Library (iphoneos_ARM64)" }))
        #expect(arm64TargetNode.detailRows.contains(where: { $0.key == "Architecture" && $0.value == "arm64" }))
        #expect(arm64TargetNode.detailCount > 0)
        let arm64ChildTitles = Set(arm64TargetNode.children.map(\.title))
        #expect(arm64ChildTitles.contains("Start"))
        #expect(arm64ChildTitles.contains("Symtab Header"))
        #expect(arm64ChildTitles.contains("Symbol Table"))
        #expect(arm64ChildTitles.contains("String Table"))

        let objectNode = try #require(arm64TargetNode.children.first(where: { $0.title.hasSuffix(".o") }))
        let objectChildTitles = objectNode.children.map(\.title)
        #expect(objectChildTitles.contains("Object Header"))

        guard case let .file(url, size) = document.hexSource else {
            Issue.record("Expected archive documents to expose a file-backed hex source.")
            return
        }

        #expect(url == fixtureURL)
        #expect(size > 0)
    }

    @Test("dynamic libraries expose a container root and per-target child nodes")
    func dynamicLibrariesExposeContainerRootAndTargetNodes() throws {
        let fixtureURL = try BrowserFixtureFactory.makeDynamicLibraryFixture()
        let service = BrowserDocumentService()

        let document = try service.load(url: fixtureURL)

        #expect(document.kind == .machOFile)
        #expect(document.rootNodes.count == 1)

        let rootNode = try #require(document.rootNodes.first)
        #expect(rootNode.title == "Dynamic Link Library")
        #expect(rootNode.childCount == 1)

        let targetNode = rootNode.child(at: 0)
        #expect(targetNode.title == "Dynamic Link Library (macos_X86_64)")
        #expect(targetNode.detailRows.contains(where: { $0.key == "File Type" && $0.value.contains("MH_DYLIB") }))
        #expect(targetNode.children.contains(where: { $0.title == "Header" }))
    }

    @Test("budgeted documents build paged symbol and string-table shells")
    func budgetedDocumentsBuildPagedSymbolAndStringTableShells() throws {
        let fixtureURL = try BrowserFixtureFactory.makeSymbolHeavyDynamicLibraryFixture(symbolCount: 520)
        let service = BrowserDocumentService()
        let scan = try MachOMetadataScanner.scan(at: fixtureURL)

        let document = try service.loadBudgeted(url: fixtureURL, scan: scan)
        let rootNode = try #require(document.rootNodes.first)
        let symbolsNode = try #require(rootNode.children.first(where: { $0.title == "Symbols" }))
        let stringTablesNode = try #require(rootNode.children.first(where: { $0.title == "String Tables" }))

        #expect(document.kind == .machOFile)
        #expect(symbolsNode.childCount > 1)
        #expect(symbolsNode.loadedChildren.isEmpty)

        let firstPageNode = symbolsNode.child(at: 0)
        #expect(firstPageNode.title.contains("Symbols"))
        #expect(firstPageNode.title.contains("0-"))
        #expect(firstPageNode.childCount > 0)

        let firstSymbolNode = firstPageNode.child(at: 0)
        #expect(firstSymbolNode.detailRows.contains(where: { $0.key == "Name" }))

        let stringTablePageNode = try #require(stringTablesNode.children.first)
        #expect(stringTablePageNode.title.contains("String Table"))
        #expect(stringTablePageNode.childCount > 0)
    }

    @Test("budgeted documents keep decoded objective-c class list entries available")
    func budgetedDocumentsKeepDecodedObjectiveCClassListEntriesAvailable() throws {
        let fixtureURL = try BrowserFixtureFactory.makeObjCDynamicLibraryFixture()
        let service = BrowserDocumentService()
        let scan = try MachOMetadataScanner.scan(at: fixtureURL)

        let document = try service.loadBudgeted(url: fixtureURL, scan: scan)
        let rootNode = try #require(document.rootNodes.first)
        let sectionsNode = try #require(rootNode.children.first(where: { $0.title == "Sections" }))
        let classListNode = try #require(sectionsNode.children.first(where: {
            $0.title.contains("__objc_classlist") || $0.title.contains("__objc_nlclslist")
        }))

        #expect(classListNode.childCount == 1)
        #expect(classListNode.detailRows.contains(where: {
            $0.key == "Objective-C Class" && $0.value == "BudgetedFixtureClass"
        }))

        if classListNode.childCount == 1 {
            let classNode = classListNode.child(at: 0)
            #expect(classNode.title == "BudgetedFixtureClass")
        }
    }

    @Test("deferred heavy groups isolate load failures to the selected node")
    func deferredHeavyGroupsIsolateLoadFailuresToTheSelectedNode() throws {
        let fixtureURL = try BrowserFixtureFactory.makeSymbolHeavyDynamicLibraryFixture(symbolCount: 64)
        let service = BrowserDocumentService()
        let scan = try MachOMetadataScanner.scan(at: fixtureURL)

        let document = try service.loadBudgeted(url: fixtureURL, scan: scan)
        try FileManager.default.removeItem(at: fixtureURL)

        let rootNode = try #require(document.rootNodes.first)
        let bindingsNode = try #require(rootNode.children.first(where: { $0.title == "Bindings" }))

        #expect(rootNode.children.contains(where: { $0.title == "Header" }))

        let failureNode = bindingsNode.child(at: 0)
        #expect(failureNode.title.contains("Failed"))
        #expect(failureNode.detailRows.contains(where: { $0.key == "Status" }))
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

    static func makeObjCDynamicLibraryFixture() throws -> URL {
        let source = """
        #import <Foundation/Foundation.h>
        @interface BudgetedFixtureClass : NSObject
        @end
        @implementation BudgetedFixtureClass
        @end
        """
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let sourceURL = tempDirectory.appendingPathComponent("budgeted-browser-fixture.m")
        let outputURL = tempDirectory.appendingPathComponent("libBudgetedBrowserFixture.dylib")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/clang")
        process.arguments = [
            "-target", "x86_64-apple-macos13.0",
            "-dynamiclib",
            sourceURL.path,
            "-framework", "Foundation",
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

    static func makeFatArchiveFixture() throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let sourceURL = tempDirectory.appendingPathComponent("browser-archive-fixture.c")
        let arm64ObjectURL = tempDirectory.appendingPathComponent("browser-archive-arm64.o")
        let x86ObjectURL = tempDirectory.appendingPathComponent("browser-archive-x86_64.o")
        let arm64ArchiveURL = tempDirectory.appendingPathComponent("libBrowserArchive-arm64.a")
        let x86ArchiveURL = tempDirectory.appendingPathComponent("libBrowserArchive-x86_64.a")
        let fatArchiveURL = tempDirectory.appendingPathComponent("libBrowserArchive-fat.a")

        try "int browser_archive_fixture(void) { return 5; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        try runTool(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "arm64-apple-ios11.0",
                "-c",
                sourceURL.path,
                "-o",
                arm64ObjectURL.path,
            ]
        )

        try runTool(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-ios11.0-simulator",
                "-c",
                sourceURL.path,
                "-o",
                x86ObjectURL.path,
            ]
        )

        try runTool(
            launchPath: "/usr/bin/libtool",
            arguments: [
                "-static",
                "-o",
                arm64ArchiveURL.path,
                arm64ObjectURL.path,
            ]
        )

        try runTool(
            launchPath: "/usr/bin/libtool",
            arguments: [
                "-static",
                "-o",
                x86ArchiveURL.path,
                x86ObjectURL.path,
            ]
        )

        try runTool(
            launchPath: "/usr/bin/lipo",
            arguments: [
                "-create",
                arm64ArchiveURL.path,
                x86ArchiveURL.path,
                "-output",
                fatArchiveURL.path,
            ]
        )

        return fatArchiveURL
    }

    static func makeDynamicLibraryFixture() throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let sourceURL = tempDirectory.appendingPathComponent("browser-dylib-fixture.c")
        let outputURL = tempDirectory.appendingPathComponent("libBrowserFixture.dylib")

        try "int browser_dylib_fixture(void) { return 9; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        try runTool(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-macos13.0",
                "-dynamiclib",
                sourceURL.path,
                "-Wl,-install_name,@rpath/libBrowserFixture.dylib",
                "-o",
                outputURL.path,
            ]
        )

        return outputURL
    }

    static func makeSymbolHeavyDynamicLibraryFixture(symbolCount: Int) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let sourceURL = tempDirectory.appendingPathComponent("browser-symbol-heavy-fixture.c")
        let outputURL = tempDirectory.appendingPathComponent("libBrowserSymbolHeavyFixture.dylib")

        let functionDefinitions = (0..<symbolCount).map { index in
            "int browser_symbol_heavy_fixture_\(index)(void) { return \(index); }"
        }.joined(separator: "\n")
        let exportCalls = (0..<symbolCount).map { index in
            "sum += browser_symbol_heavy_fixture_\(index)();"
        }.joined(separator: "\n    ")
        let source = """
        \(functionDefinitions)

        int browser_symbol_heavy_fixture_entry(void) {
            int sum = 0;
            \(exportCalls)
            return sum;
        }
        """

        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
        try runTool(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-macos13.0",
                "-dynamiclib",
                sourceURL.path,
                "-Wl,-headerpad,0x4000",
                "-Wl,-install_name,@rpath/libBrowserSymbolHeavyFixture.dylib",
                "-Wl,-rpath,@loader_path/Frameworks",
                "-o",
                outputURL.path,
            ]
        )

        return outputURL
    }

    private static func runTool(launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: launchPath)
        process.arguments = arguments

        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw BrowserFixtureError.compileFailed
        }
    }
}

private enum BrowserFixtureError: Error {
    case compileFailed
}

import CoreMachO
import Foundation
import Testing
@testable import MachOKnifeKit

struct BrowserDocumentServiceTests {
    @Test("thin Mach-O files use the MachOView layout: header, load commands, sections and link-edit tables")
    func loadsMachOFixtureWithMachOViewLayout() throws {
        let fixtureURL = try BrowserFixtureFactory.makeThinFixture()
        let document = try BrowserDocumentService().load(url: fixtureURL)

        #expect(document.kind == .machOFile)
        let rootNode = try #require(document.rootNodes.first)
        let titles = rootNode.children.map(\.title)

        #expect(titles.first == "Mach64 Header")
        #expect(titles.contains(where: { $0.hasPrefix("Load Commands (") }))
        #expect(titles.contains("Section64 (__TEXT,__text)"))
        #expect(titles.contains("Section64 (__TEXT,__cstring)"))
        #expect(titles.contains(where: { $0.hasPrefix("Symbol Table (") }))
        #expect(titles.contains("String Table"))
    }

    @Test("linked executables expose fixups, function starts and code signature structures")
    func linkedExecutablesExposeLinkEditStructures() throws {
        let fixtureURL = try BrowserFixtureFactory.makeExecutableFixture(signed: true)
        let document = try BrowserDocumentService().load(url: fixtureURL)
        let rootNode = try #require(document.rootNodes.first)
        let titles = rootNode.children.map(\.title)

        #expect(titles.contains(where: { $0 == "Chained Fixups" || $0 == "Dynamic Loader Info" }))
        #expect(titles.contains(where: { $0.hasPrefix("Function Starts") }))

        let signature = try #require(rootNode.children.first(where: { $0.title == "Code Signature" }))
        let blobTitles = signature.children.map(\.title)
        #expect(blobTitles.contains("Code Directory"))
        #expect(blobTitles.contains("Requirements"))
        let codeDirectory = try #require(signature.children.first(where: { $0.title == "Code Directory" }))
        #expect(codeDirectory.detailRows.contains(where: { $0.key == "Identifier" && $0.value.isEmpty == false }))
    }

    @Test("chained fixups decode imports and fixup chains")
    func chainedFixupsDecodeImportsAndChains() throws {
        let fixtureURL = try BrowserFixtureFactory.makeChainedFixupsExecutableFixture()
        let document = try BrowserDocumentService().load(url: fixtureURL)
        let rootNode = try #require(document.rootNodes.first)
        let fixups = try #require(rootNode.children.first(where: { $0.title == "Chained Fixups" }))

        let imports = try #require(fixups.children.first(where: { $0.title.hasPrefix("Imports (") }))
        #expect(imports.detailCount > 0)
        #expect((0..<imports.detailCount).contains(where: { imports.detailRow(at: $0).key.contains("_printf") }))

        let chain = try #require(fixups.children.first(where: { $0.title.hasPrefix("Fixups (") }))
        #expect(chain.detailCount > 0)
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

    @Test("header rows show file offsets, raw data and semantic values")
    func headerDetailRowsUseSemanticNames() throws {
        let fixtureURL = try BrowserFixtureFactory.makeThinFixture()
        let document = try BrowserDocumentService().load(url: fixtureURL)
        let rootNode = try #require(document.rootNodes.first)
        let headerNode = try #require(rootNode.children.first(where: { $0.title == "Mach64 Header" }))

        let magicRow = try #require(headerNode.detailRows.first(where: { $0.key == "Magic Number" }))
        let cpuTypeRow = try #require(headerNode.detailRows.first(where: { $0.key == "CPU Type" }))

        #expect(magicRow.value == "MH_MAGIC_64")
        #expect(magicRow.rawAddress == 0)
        #expect(magicRow.dataPreview == "FEEDFACF")
        #expect(cpuTypeRow.value == "CPU_TYPE_X86_64")
        #expect(cpuTypeRow.rawAddress == 4)
    }

    @Test("root node exposes semantic Mach-O summary")
    func rootNodeExposesSemanticSummary() throws {
        let fixtureURL = try BrowserFixtureFactory.makeThinFixture()
        let document = try BrowserDocumentService().load(url: fixtureURL)
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

    @Test("objective-c class list lazily exposes class nodes")
    func objectiveCClassListLazilyExposesClassNames() throws {
        let fixtureURL = try BrowserFixtureFactory.makeObjCFixture()
        let document = try BrowserDocumentService().load(url: fixtureURL)
        let rootNode = try #require(document.rootNodes.first)
        let classListNode = try #require(rootNode.children.first(where: { $0.title == "Section64 (__DATA,__objc_classlist)" }))

        #expect(classListNode.loadedChildren.isEmpty)
        #expect(classListNode.detailRows.contains(where: { $0.key == "Objective-C Class" && $0.value == "BrowserFixtureClass" }))

        let classNode = classListNode.child(at: 0)
        #expect(classNode.title == "BrowserFixtureClass")
        #expect(classNode.detailRows.contains(where: { $0.key == "Name" && $0.value == "BrowserFixtureClass" }))
    }

    @Test("objective-c category and method-name sections decode their contents")
    func objectiveCCategoryAndMethodNameSectionsExposeSymbolicChildren() throws {
        let fixtureURL = try BrowserFixtureFactory.makeObjCCategoryFixture()
        let document = try BrowserDocumentService().load(url: fixtureURL)
        let rootNode = try #require(document.rootNodes.first)

        let categoryListNode = try #require(rootNode.children.first(where: { $0.title == "Section64 (__DATA,__objc_catlist)" }))
        let methodNameNode = try #require(rootNode.children.first(where: { $0.title == "Section64 (__TEXT,__objc_methname)" }))

        let summaryRow = try #require(categoryListNode.detailRows.first(where: { $0.key == "Objective-C Category" }))
        #expect(summaryRow.value == "BrowserFixtureClass(Extra)")
        #expect(categoryListNode.child(at: 0).title == "BrowserFixtureClass(Extra)")

        let methodNames = methodNameNode.detailRows.map(\.value)
        #expect(methodNames.contains("baseMethod"))
        #expect(methodNames.contains("categoryMethod"))
    }

    @Test("symbol table rows decode nlist fields and two-level library ordinals")
    func symbolTableRowsDecodeNlistFields() throws {
        let fixtureURL = try BrowserFixtureFactory.makeObjCDynamicLibraryFixture()
        let document = try BrowserDocumentService().load(url: fixtureURL)
        let rootNode = try #require(document.rootNodes.first).child(at: 0)
        let symbols = try #require(rootNode.children.first(where: { $0.title.hasPrefix("Symbol Table (") }))
        let rows = (0..<symbols.detailCount).map(symbols.detailRow(at:))

        let undefinedIndex = try #require(rows.firstIndex(where: { $0.key == "String Table Index" && $0.value == "_OBJC_CLASS_$_NSObject" }))
        let descriptionRow = rows[undefinedIndex + 3]
        #expect(descriptionRow.key == "Description")
        #expect(descriptionRow.value.contains("Library:"))
        #expect(descriptionRow.value.contains("N_SYMBOL_RESOLVER") == false)
        #expect(descriptionRow.value.contains("N_ALT_ENTRY") == false)
    }

    @Test("load command nodes expose command lists and layout details")
    func loadCommandNodesExposeCommandListsAndLayoutDetails() throws {
        let fixtureURL = try BrowserFixtureFactory.makeExecutableFixture()
        let document = try BrowserDocumentService().load(url: fixtureURL)
        let rootNode = try #require(document.rootNodes.first)
        let loadCommandsNode = try #require(rootNode.children.first(where: { $0.title.hasPrefix("Load Commands") }))

        #expect(loadCommandsNode.detailCount == loadCommandsNode.childCount)
        #expect(loadCommandsNode.title == "Load Commands (\(loadCommandsNode.childCount))")

        let commandNode = loadCommandsNode.child(at: 0)
        #expect(commandNode.detailRows.contains(where: { $0.key == "Command" }))
        #expect(commandNode.detailRows.contains(where: { $0.key == "Command Size" }))

        let dylibNode = try #require(loadCommandsNode.children.first(where: { $0.title == "LC_LOAD_DYLIB (libSystem.B.dylib)" }))
        let nameRow = try #require(dylibNode.detailRows.first(where: { $0.key == "Name" }))
        #expect(nameRow.value == "/usr/lib/libSystem.B.dylib")
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
        #expect(objectChildTitles.contains("Mach64 Header"))

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
        let document = try BrowserDocumentService().load(url: fixtureURL)

        #expect(document.kind == .machOFile)
        #expect(document.rootNodes.count == 1)

        let rootNode = try #require(document.rootNodes.first)
        #expect(rootNode.title == "Dynamic Link Library")
        #expect(rootNode.childCount == 1)

        let targetNode = rootNode.child(at: 0)
        #expect(targetNode.title == "Dynamic Link Library (macos_X86_64)")
        #expect(targetNode.detailRows.contains(where: { $0.key == "File Type" && $0.value.contains("MH_DYLIB") }))
        #expect(targetNode.children.contains(where: { $0.title == "Mach64 Header" }))
    }

    @Test("budgeted documents page large symbol and string tables through indexed rows")
    func budgetedDocumentsPageLargeTables() throws {
        let fixtureURL = try BrowserFixtureFactory.makeSymbolHeavyDynamicLibraryFixture(symbolCount: 520)
        let service = BrowserDocumentService()
        let scan = try MachOMetadataScanner.scan(at: fixtureURL)

        let document = try service.loadBudgeted(url: fixtureURL, scan: scan)
        let imageNode = try #require(document.rootNodes.first).child(at: 0)
        let symbolsNode = try #require(imageNode.children.first(where: { $0.title.hasPrefix("Symbol Table (") }))
        let stringTableNode = try #require(imageNode.children.first(where: { $0.title == "String Table" }))

        #expect(document.kind == .machOFile)
        #expect(symbolsNode.detailCount >= 520 * 5)
        #expect(symbolsNode.detailRow(at: 0).key == "String Table Index")
        #expect(stringTableNode.detailCount > 520)
        #expect(stringTableNode.detailRow(at: stringTableNode.detailCount - 1).rawAddress != nil)
    }

    @Test("budgeted documents keep decoded objective-c class list entries available")
    func budgetedDocumentsKeepDecodedObjectiveCClassListEntriesAvailable() throws {
        let fixtureURL = try BrowserFixtureFactory.makeObjCDynamicLibraryFixture()
        let service = BrowserDocumentService()
        let scan = try MachOMetadataScanner.scan(at: fixtureURL)

        let document = try service.loadBudgeted(url: fixtureURL, scan: scan)
        let imageNode = try #require(document.rootNodes.first).child(at: 0)
        let classListNode = try #require(imageNode.children.first(where: { $0.title.contains("__objc_classlist") }))

        #expect(classListNode.childCount == 1)
        #expect(classListNode.detailRows.contains(where: {
            $0.key == "Objective-C Class" && $0.value == "BudgetedFixtureClass"
        }))
        #expect(classListNode.child(at: 0).title == "BudgetedFixtureClass")
    }

    @Test("code signature blob titles follow cs_blobs.h magics")
    func codeSignatureBlobTitlesFollowMagics() {
        #expect(MachOLayoutBuilder.codeSignatureBlobTitle(slot: 0x10000, magic: 0xFADE_0B01) == "Signature (CMS)")
        #expect(MachOLayoutBuilder.codeSignatureBlobTitle(slot: 0, magic: 0xFADE_0C02) == "Code Directory")
        #expect(MachOLayoutBuilder.codeSignatureBlobTitle(slot: 0x1000, magic: 0xFADE_0C02) == "Alternate Code Directory")
        #expect(MachOConstants.codeSignatureMagicName(0xFADE_0B01) == "CSMAGIC_BLOBWRAPPER")
        #expect(MachOConstants.codeSignatureMagicName(0xFADE_0B02) == "CSMAGIC_EMBEDDED_SIGNATURE_OLD")
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

    static func makeChainedFixupsExecutableFixture() throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let sourceURL = tempDirectory.appendingPathComponent("chained-fixture.c")
        let outputURL = tempDirectory.appendingPathComponent("chained-fixture")
        try """
        #include <stdio.h>
        static const char *greeting = "hello";
        const char **greeting_ref = &greeting;
        int main(void) { printf("%s\\n", *greeting_ref); return 0; }
        """.write(to: sourceURL, atomically: true, encoding: .utf8)
        try runTool(
            launchPath: "/usr/bin/clang",
            arguments: ["-target", "arm64-apple-macos13.0", sourceURL.path, "-o", outputURL.path]
        )
        return outputURL
    }

    static func makeExecutableFixture(signed: Bool = false) throws -> URL {
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
        if signed {
            try runTool(launchPath: "/usr/bin/codesign", arguments: ["-s", "-", "-f", outputURL.path])
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

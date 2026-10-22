import CoreMachO
import Foundation
import Testing
@testable import MachOKnifeKit

struct MergeSplitServiceTests {
    @Test("merging into one of the inputs keeps the input readable and produces a universal binary")
    func mergeIntoOneOfTheInputs() throws {
        let fixture = try MergeFixture.make()

        // 旧实现先删除输出文件再运行 lipo：输出路径等于第一个输入时，输入在被读取前就没了。
        try MachOMergeSplitService().merge(inputURLs: [fixture.x86URL, fixture.armURL], outputURL: fixture.x86URL)

        #expect(try MachOMergeSplitService().availableArchitectures(for: fixture.x86URL) == ["arm64", "x86_64"])
        #expect(try MergeFixture.temporaryFiles(in: fixture.directory).isEmpty)
    }

    @Test("a failing merge leaves an existing output file untouched and no temporary file behind")
    func failingMergeKeepsExistingOutput() throws {
        let fixture = try MergeFixture.make()
        let outputURL = fixture.directory.appendingPathComponent("existing-output")
        try Data("keep me".utf8).write(to: outputURL)

        // 两个输入架构相同，lipo -create 会失败。
        #expect(throws: MachOToolServiceError.self) {
            try MachOMergeSplitService().merge(inputURLs: [fixture.x86URL, fixture.x86URL], outputURL: outputURL)
        }

        #expect(try Data(contentsOf: outputURL) == Data("keep me".utf8))
        #expect(try MergeFixture.temporaryFiles(in: fixture.directory).isEmpty)
    }

    @Test("splitting a mixed-architecture thin archive keeps only the requested architecture's members")
    func splitMixedThinArchiveFiltersMembers() throws {
        let fixture = try ToolFixtureFactory.makeMixedArchive(thin: true)
        let outputDirectory = fixture.directory.appendingPathComponent("split", isDirectory: true)

        let outputs = try MachOMergeSplitService().split(
            inputURL: fixture.archiveURL,
            architectures: ["arm64", "x86_64"],
            outputDirectoryURL: outputDirectory
        )

        #expect(outputs.map(\.lastPathComponent) == ["libMixed-arm64.a", "libMixed-x86_64.a"])
        let inspector = ArchiveInspector()
        let arm64 = try #require(try inspector.inspect(url: outputs[0]))
        let x86 = try #require(try inspector.inspect(url: outputs[1]))
        // 旧实现把整个混合归档原样复制成两个“单架构”文件，两个输出都会同时包含 arm64 与 x86_64。
        #expect(arm64.architectures == ["arm64"])
        #expect(x86.architectures == ["x86_64"])
        #expect(try inspector.listMembers(in: outputs[0]).filter { ArchiveInspector.isSymbolTableMemberName($0) == false } == ["dup.o", "dup.o"])
        #expect(try inspector.listMembers(in: outputs[1]).filter { ArchiveInspector.isSymbolTableMemberName($0) == false } == ["intel.o"])
    }

    @Test("removing architectures rewrites a universal binary in place")
    func removeArchitecturesFromUniversalBinary() throws {
        let fixture = try MergeFixture.make()
        let universalURL = fixture.directory.appendingPathComponent("libUniversal.dylib")
        let service = MachOMergeSplitService()
        try service.merge(inputURLs: [fixture.x86URL, fixture.armURL], outputURL: universalURL)

        try service.removeArchitectures(["x86_64"], from: universalURL, outputURL: universalURL)

        #expect(try service.availableArchitectures(for: universalURL) == ["arm64"])
        #expect(try MergeFixture.temporaryFiles(in: fixture.directory).isEmpty)
    }

    @Test("removing architectures from a fat static library keeps the remaining slices")
    func removeArchitecturesFromFatArchive() throws {
        let fixture = try ToolFixtureFactory.makeMixedArchive(thin: false)
        let outputURL = fixture.directory.appendingPathComponent("libArm64Only.a")

        try MachOMergeSplitService().removeArchitectures(["x86_64"], from: fixture.archiveURL, outputURL: outputURL)

        let inspection = try #require(try ArchiveInspector().inspect(url: outputURL))
        #expect(inspection.architectures == ["arm64"])
    }

    @Test("removing architectures rejects thin inputs, unknown architectures and removing everything")
    func removeArchitecturesRejectsInvalidRequests() throws {
        let fixture = try MergeFixture.make()
        let universalURL = fixture.directory.appendingPathComponent("libUniversal.dylib")
        let outputURL = fixture.directory.appendingPathComponent("out.dylib")
        let service = MachOMergeSplitService()
        try service.merge(inputURLs: [fixture.x86URL, fixture.armURL], outputURL: universalURL)

        #expect {
            try service.removeArchitectures(["x86_64"], from: fixture.x86URL, outputURL: outputURL)
        } throws: { error in
            guard case .notUniversal = error as? MachOToolServiceError else {
                return false
            }
            return true
        }
        #expect {
            try service.removeArchitectures(["armv7"], from: universalURL, outputURL: outputURL)
        } throws: { error in
            guard case let .architectureNotFound(name, _) = error as? MachOToolServiceError else {
                return false
            }
            return name == "armv7"
        }
        #expect {
            try service.removeArchitectures(["arm64", "x86_64"], from: universalURL, outputURL: outputURL)
        } throws: { error in
            guard case .cannotRemoveAllArchitectures = error as? MachOToolServiceError else {
                return false
            }
            return true
        }
        #expect(FileManager.default.fileExists(atPath: outputURL.path) == false)
    }
}

struct ToolReportJSONTests {
    @Test("text reports render sorted, structured JSON including empty sections")
    func textReportRendersJSON() throws {
        let report = ToolTextReport(
            title: "libFoo.a",
            summaryLines: ["Path: /tmp/libFoo.a"],
            sections: [
                ToolReportSection(title: "arm64", lines: ["Members: 2"]),
                ToolReportSection(title: "Empty", lines: []),
            ]
        )

        let object = try #require(try JSONSerialization.jsonObject(with: Data(report.renderedJSON.utf8)) as? [String: Any])
        #expect(object["title"] as? String == "libFoo.a")
        #expect(object["summary"] as? [String] == ["Path: /tmp/libFoo.a"])
        let sections = try #require(object["sections"] as? [[String: Any]])
        #expect(sections.map { $0["title"] as? String } == ["arm64", "Empty"])
        #expect(sections.first?["lines"] as? [String] == ["Members: 2"])
        // 不转义斜杠，便于人工阅读。
        #expect(report.renderedJSON.contains("/tmp/libFoo.a"))
    }

    @Test("contamination reports include counts in their JSON form")
    func contaminationReportRendersJSON() throws {
        let fixture = try ToolFixtureFactory.makeMixedArchive(thin: true)
        let report = try BinaryContaminationCheckService().runCheck(at: fixture.archiveURL, target: "arm64", mode: .architecture)

        let object = try #require(try JSONSerialization.jsonObject(with: Data(report.renderedJSON.utf8)) as? [String: Any])
        #expect(object["mode"] as? String == "architecture")
        #expect(object["target"] as? String == "arm64")
        #expect(object["okCount"] as? Int == 2)
        #expect(object["mismatchCount"] as? Int == 1)
        #expect(object["uncheckedCount"] as? Int == 0)
        #expect((object["report"] as? [String: Any])?["title"] as? String == "libMixed.a")
    }
}

struct XCFrameworkBuildOutputTests {
    @Test("the reported output path is the last absolute .xcframework line")
    func reportedOutputPathIsLastAbsoluteLine() {
        let output = """
        xcframework successfully written out to: /tmp/scratch/SDK.xcframework
        /Users/me/Output/SDK.xcframework
        """
        #expect(XCFrameworkBuildTool.reportedOutputURL(in: output)?.path == "/Users/me/Output/SDK.xcframework")
        #expect(XCFrameworkBuildTool.reportedOutputURL(in: "xcframework successfully written out to: /tmp/x/SDK.xcframework") == nil)
        #expect(XCFrameworkBuildTool.reportedOutputURL(in: "") == nil)
    }

    @Test("multi-byte characters split across pipe chunks are not dropped")
    func multiByteCharactersAcrossChunks() {
        let forwarded = ForwardedText()
        let collector = XCFrameworkBuildOutputCollector { forwarded.append($0) }
        let bytes = Array("构建完成\n".utf8)

        // 在一个三字节汉字中间切开：旧实现对第一块调用 String(data:encoding:) 得到 nil，整块被丢弃。
        collector.append(Data(bytes[0..<4]))
        collector.append(Data(bytes[4...]))
        collector.finish()

        #expect(collector.value == "构建完成\n")
        #expect(forwarded.value == "构建完成\n")
    }

    @Test("incomplete UTF-8 tails are held back until the next chunk")
    func completeUTF8PrefixLength() {
        #expect(XCFrameworkBuildOutputCollector.completeUTF8PrefixLength(Data("abc".utf8)) == 3)
        #expect(XCFrameworkBuildOutputCollector.completeUTF8PrefixLength(Data([0x61, 0xE6, 0x9E])) == 1)
        #expect(XCFrameworkBuildOutputCollector.completeUTF8PrefixLength(Data([0xE6, 0x9E, 0x84])) == 3)
        #expect(XCFrameworkBuildOutputCollector.completeUTF8PrefixLength(Data([0x61, 0xF0, 0x9F, 0x98])) == 1)
        #expect(XCFrameworkBuildOutputCollector.completeUTF8PrefixLength(Data()) == 0)
    }
}

/// 线程安全地累积 outputHandler 收到的文本。
private final class ForwardedText: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    func append(_ text: String) {
        lock.lock()
        storage += text
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer {
            lock.unlock()
        }
        return storage
    }
}

private struct MergeFixture {
    let directory: URL
    let x86URL: URL
    let armURL: URL

    /// 两个单架构 dylib（x86_64 与 arm64），用于 merge / remove 测试。
    static func make() throws -> MergeFixture {
        let directory = try ToolFixtureFactory.makeDirectory()
        let sourceURL = directory.appendingPathComponent("merge.c")
        try "int merge_symbol(void) { return 5; }\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        let x86URL = directory.appendingPathComponent("libMerge-x86_64.dylib")
        let armURL = directory.appendingPathComponent("libMerge-arm64.dylib")
        try ToolFixtureFactory.run("/usr/bin/clang", arguments: [
            "-target", "x86_64-apple-macos13.0", "-dynamiclib", sourceURL.path, "-o", x86URL.path,
        ])
        try ToolFixtureFactory.run("/usr/bin/clang", arguments: [
            "-target", "arm64-apple-macos13.0", "-dynamiclib", sourceURL.path, "-o", armURL.path,
        ])
        return MergeFixture(directory: directory, x86URL: x86URL, armURL: armURL)
    }

    static func temporaryFiles(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".tmp") }
    }
}

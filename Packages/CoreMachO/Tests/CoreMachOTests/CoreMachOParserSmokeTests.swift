import Foundation
import MachO
import Testing
@testable import CoreMachO

struct CoreMachOParserSmokeTests {
    @Test("parses a thin Mach-O fixture")
    func parsesThinMachOFixture() throws {
        let fixtureURL = try MachOTestFixtureFactory.makeThinFixture()

        let container = try MachOContainer.parse(at: fixtureURL)

        #expect(container.slices.count == 1)
        #expect(container.kind == .thin)
        let slice = try #require(container.slices.first)
        #expect(slice.offset == 0)
        #expect(slice.is64Bit)
        #expect(slice.header.cpuType == CPU_TYPE_X86_64)
        #expect(slice.header.fileType == UInt32(MH_OBJECT))
        #expect(slice.symbols.contains(where: { $0.name == "_machoknife_fixture" }))
    }

    @Test("parses a fat Mach-O fixture")
    func parsesFatMachOFixture() throws {
        let fixtureURL = try MachOTestFixtureFactory.makeFatFixture()

        let container = try MachOContainer.parse(at: fixtureURL)

        #expect(container.kind == .fat)
        #expect(container.slices.count == 2)
        // 两个切片的架构分别是 x86_64 与 arm64，且偏移都在 fat 头之后。
        let architectures = Set(container.slices.map {
            MachOArchitectureNaming.name(cpuType: $0.header.cpuType, cpuSubtype: $0.header.cpuSubtype)
        })
        #expect(architectures == ["x86_64", "arm64"])
        #expect(container.slices.allSatisfy { $0.offset > 0 })
    }

    @Test("parses a fat executable fixture with symbol tables")
    func parsesFatExecutableFixtureWithSymbolTables() throws {
        let fixtureURL = try MachOTestFixtureFactory.makeFatExecutableFixture()

        let container = try MachOContainer.parse(at: fixtureURL)

        #expect(container.kind == .fat)
        #expect(container.slices.count == 2)
        #expect(container.slices.allSatisfy { $0.symbols.isEmpty == false })
    }

    @Test("enumerates load commands from a fixture")
    func enumeratesLoadCommandsFromFixture() throws {
        let fixtureURL = try MachOTestFixtureFactory.makeThinFixture()

        let container = try MachOContainer.parse(at: fixtureURL)

        let slice = try #require(container.slices.first)
        #expect(slice.loadCommands.count == Int(slice.header.numberOfCommands))
        #expect(slice.loadCommands.reduce(0) { $0 + Int($1.size) } == Int(slice.header.sizeofCommands))
        #expect(slice.loadCommands.contains(where: { $0.command == UInt32(LC_SYMTAB) }))
        #expect(slice.loadCommands.contains(where: { $0.command == UInt32(LC_SEGMENT_64) }))
    }
}

private enum MachOTestFixtureFactory {
    static func makeThinFixture() throws -> URL {
        let source = """
        int machoknife_fixture(void) { return 42; }
        """
        let tempDirectory = try makeTemporaryDirectory()
        let sourceURL = tempDirectory.appendingPathComponent("thin.c")
        let outputURL = tempDirectory.appendingPathComponent("thin.o")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

        try Shell.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-macos13.0",
                "-c",
                sourceURL.path,
                "-o",
                outputURL.path,
            ]
        )
        return outputURL
    }

    static func makeFatFixture() throws -> URL {
        let source = """
        int machoknife_fixture(void) { return 7; }
        """
        let tempDirectory = try makeTemporaryDirectory()
        let sourceURL = tempDirectory.appendingPathComponent("fat.c")
        let x86URL = tempDirectory.appendingPathComponent("fat-x86_64.o")
        let armURL = tempDirectory.appendingPathComponent("fat-arm64.o")
        let outputURL = tempDirectory.appendingPathComponent("fat-universal.o")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

        try Shell.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-macos13.0",
                "-c",
                sourceURL.path,
                "-o",
                x86URL.path,
            ]
        )
        try Shell.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "arm64-apple-macos13.0",
                "-c",
                sourceURL.path,
                "-o",
                armURL.path,
            ]
        )
        try Shell.run(
            launchPath: "/usr/bin/lipo",
            arguments: [
                "-create",
                x86URL.path,
                armURL.path,
                "-output",
                outputURL.path,
            ]
        )
        return outputURL
    }

    static func makeFatExecutableFixture() throws -> URL {
        let source = """
        #include <stdio.h>
        int main(void) {
            puts("machoknife-fat-exec");
            return 0;
        }
        """
        let tempDirectory = try makeTemporaryDirectory()
        let sourceURL = tempDirectory.appendingPathComponent("fat-exec.c")
        let x86URL = tempDirectory.appendingPathComponent("fat-exec-x86_64")
        let armURL = tempDirectory.appendingPathComponent("fat-exec-arm64")
        let outputURL = tempDirectory.appendingPathComponent("fat-exec-universal")
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)

        try Shell.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "x86_64-apple-macos13.0",
                sourceURL.path,
                "-o",
                x86URL.path,
            ]
        )
        try Shell.run(
            launchPath: "/usr/bin/clang",
            arguments: [
                "-target", "arm64-apple-macos13.0",
                sourceURL.path,
                "-o",
                armURL.path,
            ]
        )
        try Shell.run(
            launchPath: "/usr/bin/lipo",
            arguments: [
                "-create",
                x86URL.path,
                armURL.path,
                "-output",
                outputURL.path,
            ]
        )
        return outputURL
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private enum Shell {
    static func run(launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: launchPath)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "unknown error"
            throw ShellError.commandFailed(launchPath: launchPath, arguments: arguments, output: errorOutput)
        }
    }
}

private enum ShellError: Error {
    case commandFailed(launchPath: String, arguments: [String], output: String)
}

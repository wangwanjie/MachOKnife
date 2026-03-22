import Foundation
import MachOKnifeKit

struct BuildXCFrameworkCommand {
    static let name = "build-xcframework"
    static let usage = """
    machoe-cli build-xcframework --library <path> [--library <path> ...] --headers <path> [--headers <path> ...] --output <path>
    machoe-cli build-xcframework --source-library <path> [--ios-device-source-library <path>] [--ios-simulator-source-library <path>] [--maccatalyst-source-library <path>] --headers-dir <path> (--output <path> | --output-dir <path> [--xcframework-name <name>]) [--output-library-name <name>] [--module-name <name>] [--umbrella-header <name>] [--maccatalyst-min-version <version>] [--maccatalyst-sdk-version <version>]
    """

    static func run(arguments: [String]) throws -> String {
        if arguments.contains("--source-library") || arguments.contains("--ios-device-source-library") || arguments.contains("--ios-simulator-source-library") || arguments.contains("--maccatalyst-source-library") {
            return try runAdvancedBuild(arguments: arguments)
        }

        let libraryPaths = CLICommandSupport.repeatedOptions("--library", in: arguments)
        let headerPaths = CLICommandSupport.repeatedOptions("--headers", in: arguments)
        guard libraryPaths.isEmpty == false else {
            throw CLIError.invalidUsage(usage)
        }
        guard headerPaths.isEmpty == false else {
            throw CLIError.invalidUsage(usage)
        }

        let libraries = libraryPaths.map { URL(filePath: $0) }
        let headers = try normalizedHeaders(headerPaths: headerPaths, libraryCount: libraries.count)
        let outputURL = URL(filePath: try CLICommandSupport.requiredOption("--output", in: arguments, usage: usage))

        try createParentDirectoryIfNeeded(for: outputURL)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        var commandArguments = ["-create-xcframework"]
        for (libraryURL, headersURL) in zip(libraries, headers) {
            commandArguments += ["-library", libraryURL.path, "-headers", headersURL.path]
        }
        commandArguments += ["-output", outputURL.path]

        let output = try runProcess(
            executableURL: URL(filePath: "/usr/bin/xcodebuild"),
            arguments: commandArguments
        )

        var lines = ["XCFramework output: \(outputURL.path)"]
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOutput.isEmpty == false {
            lines += ["", trimmedOutput]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func normalizedHeaders(headerPaths: [String], libraryCount: Int) throws -> [URL] {
        if headerPaths.count == 1 {
            let headerURL = URL(filePath: headerPaths[0])
            return Array(repeating: headerURL, count: libraryCount)
        }
        guard headerPaths.count == libraryCount else {
            throw CLIError.invalidUsage(usage)
        }
        return headerPaths.map { URL(filePath: $0) }
    }

    private static func createParentDirectoryIfNeeded(for outputURL: URL) throws {
        let parentDirectoryURL = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)
    }

    private static func runProcess(executableURL: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "MachOKnife.CLI",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }

        return output
    }

    private static func runAdvancedBuild(arguments: [String]) throws -> String {
        let sourceLibraryURL = URL(filePath: try CLICommandSupport.requiredOption("--source-library", in: arguments, usage: usage))
        let deviceLibraryURL = CLICommandSupport.optionalOption("--ios-device-source-library", in: arguments).map { URL(filePath: $0) }
        let simulatorLibraryURL = CLICommandSupport.optionalOption("--ios-simulator-source-library", in: arguments).map { URL(filePath: $0) }
        let macCatalystLibraryURL = CLICommandSupport.optionalOption("--maccatalyst-source-library", in: arguments).map { URL(filePath: $0) }
        let headersDirectoryURL = URL(filePath: try CLICommandSupport.requiredOption("--headers-dir", in: arguments, usage: usage))

        let explicitOutputURL = CLICommandSupport.optionalOption("--output", in: arguments).map { URL(filePath: $0) }
        let outputDirectoryURL: URL
        let xcframeworkName: String
        if let explicitOutputURL {
            outputDirectoryURL = explicitOutputURL.deletingLastPathComponent()
            xcframeworkName = explicitOutputURL.lastPathComponent
        } else {
            outputDirectoryURL = URL(filePath: try CLICommandSupport.requiredOption("--output-dir", in: arguments, usage: usage))
            xcframeworkName = CLICommandSupport.optionalOption("--xcframework-name", in: arguments) ?? "SDK.xcframework"
        }

        let request = XCFrameworkBuildRequest(
            sourceLibraryURL: sourceLibraryURL,
            iosDeviceSourceLibraryURL: deviceLibraryURL,
            iosSimulatorSourceLibraryURL: simulatorLibraryURL,
            macCatalystSourceLibraryURL: macCatalystLibraryURL,
            headersDirectoryURL: headersDirectoryURL,
            outputDirectoryURL: outputDirectoryURL,
            outputLibraryName: CLICommandSupport.optionalOption("--output-library-name", in: arguments) ?? "libSDK.a",
            xcframeworkName: xcframeworkName,
            moduleName: CLICommandSupport.optionalOption("--module-name", in: arguments),
            umbrellaHeader: CLICommandSupport.optionalOption("--umbrella-header", in: arguments),
            macCatalystMinimumVersion: CLICommandSupport.optionalOption("--maccatalyst-min-version", in: arguments) ?? "13.1",
            macCatalystSDKVersion: CLICommandSupport.optionalOption("--maccatalyst-sdk-version", in: arguments) ?? "17.5"
        )

        let outputCollector = CLIXCFrameworkOutputCollector()
        let outputURL = try XCFrameworkBuildTool().build(request: request) { chunk in
            outputCollector.append(chunk)
        }

        var lines = ["XCFramework output: \(outputURL.path)"]
        let trimmedOutput = outputCollector.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOutput.isEmpty == false {
            lines += ["", trimmedOutput]
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

private final class CLIXCFrameworkOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var storage = ""

    nonisolated func append(_ text: String) {
        lock.lock()
        storage += text
        lock.unlock()
    }

    nonisolated var value: String {
        lock.lock()
        let value = storage
        lock.unlock()
        return value
    }
}

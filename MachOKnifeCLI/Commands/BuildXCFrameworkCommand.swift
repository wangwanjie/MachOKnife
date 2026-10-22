import Foundation
import MachOKnifeKit

struct BuildXCFrameworkCommand {
    static let name = "build-xcframework"
    static let usage = """
    machoe-cli build-xcframework --library <path> [--library <path> ...] --headers <path> [--headers <path> ...] --output <path>
    machoe-cli build-xcframework --source-library <path> [--ios-device-source-library <path>] [--ios-simulator-source-library <path>] [--maccatalyst-source-library <path>] --headers-dir <path> (--output <path> | --output-dir <path> [--xcframework-name <name>]) [--output-library-name <name>] [--module-name <name>] [--umbrella-header <name>] [--maccatalyst-min-version <version>] [--maccatalyst-sdk-version <version>]
    """

    private static let simpleValueOptions: Set<String> = ["--library", "--headers", "--output"]
    private static let advancedValueOptions: Set<String> = [
        "--source-library",
        "--ios-device-source-library",
        "--ios-simulator-source-library",
        "--maccatalyst-source-library",
        "--headers-dir",
        "--output",
        "--output-dir",
        "--xcframework-name",
        "--output-library-name",
        "--module-name",
        "--umbrella-header",
        "--maccatalyst-min-version",
        "--maccatalyst-sdk-version",
    ]
    private static let advancedModeMarkers: Set<String> = [
        "--source-library",
        "--ios-device-source-library",
        "--ios-simulator-source-library",
        "--maccatalyst-source-library",
    ]

    static func run(arguments: [String]) throws -> String {
        let isAdvanced = arguments.contains { argument in
            advancedModeMarkers.contains(argument) || advancedModeMarkers.contains(where: { argument.hasPrefix($0 + "=") })
        }
        if isAdvanced {
            let parsed = try CLICommandSupport.parse(arguments, valueOptions: advancedValueOptions, usage: usage)
            return try runAdvancedBuild(parsed)
        }

        // 简单模式下 `--library` / `--headers` 可以重复（每个库一组头文件），`--output` 只能出现一次。
        let parsed = try CLICommandSupport.parse(
            arguments,
            valueOptions: simpleValueOptions,
            repeatableOptions: ["--library", "--headers"],
            usage: usage
        )
        guard parsed.positionals.isEmpty else {
            throw CLIError.invalidUsage(usage, detail: "unexpected argument '\(parsed.positionals[0])'")
        }
        let libraryPaths = parsed.values("--library")
        let headerPaths = parsed.values("--headers")
        guard libraryPaths.isEmpty == false else {
            throw CLIError.invalidUsage(usage, detail: "missing required option '--library'")
        }
        guard headerPaths.isEmpty == false else {
            throw CLIError.invalidUsage(usage, detail: "missing required option '--headers'")
        }

        let libraries = libraryPaths.map { URL(filePath: $0) }
        let headers = try normalizedHeaders(headerPaths: headerPaths, libraryCount: libraries.count)
        let outputURL = try validatedXCFrameworkOutputURL(parsed.requiredValue("--output", usage: usage))

        try createParentDirectoryIfNeeded(for: outputURL)

        // 先在暂存目录里生成 xcframework，成功后再替换旧产物：
        // 之前的实现在调用 xcodebuild 之前就删除了已有的输出，一旦构建失败，用户原有的 xcframework 会丢失。
        let fileManager = FileManager.default
        let stagingDirectoryURL = try makeStagingDirectory(near: outputURL)
        defer {
            try? fileManager.removeItem(at: stagingDirectoryURL)
        }
        let stagedOutputURL = stagingDirectoryURL.appendingPathComponent(outputURL.lastPathComponent, isDirectory: true)

        var commandArguments = ["-create-xcframework"]
        for (libraryURL, headersURL) in zip(libraries, headers) {
            commandArguments += ["-library", libraryURL.path, "-headers", headersURL.path]
        }
        commandArguments += ["-output", stagedOutputURL.path]

        let output = try runProcess(
            executableURL: URL(filePath: "/usr/bin/xcodebuild"),
            arguments: commandArguments
        )

        // Only ever delete a previous .xcframework bundle; never an arbitrary user path.
        try removeExistingXCFramework(at: outputURL)
        try fileManager.moveItem(at: stagedOutputURL, to: outputURL)

        var lines = ["XCFramework output: \(outputURL.path)"]
        // xcodebuild 的日志里引用的是暂存路径，替换回最终输出路径，避免把临时目录暴露给用户。
        let trimmedOutput = output
            .replacingOccurrences(of: stagedOutputURL.path, with: outputURL.path)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
            throw CLIError.invalidUsage(usage, detail: "pass either one --headers value or one per --library")
        }
        return headerPaths.map { URL(filePath: $0) }
    }

    /// Validates that `name` is a plain file name (no path separators) ending in `.xcframework`.
    static func isValidXCFrameworkName(_ name: String) -> Bool {
        guard name.contains("/") == false,
              name != ".xcframework",
              name.hasPrefix(".") == false,
              (name as NSString).pathExtension == "xcframework" else {
            return false
        }
        return true
    }

    private static func validatedXCFrameworkOutputURL(_ path: String) throws -> URL {
        let outputURL = URL(filePath: path).standardizedFileURL
        guard isValidXCFrameworkName(outputURL.lastPathComponent) else {
            throw CLIError.invalidUsage(usage, detail: "--output must name a bundle ending in .xcframework (got '\(path)')")
        }
        return outputURL
    }

    private static func removeExistingXCFramework(at outputURL: URL) throws {
        guard outputURL.pathExtension == "xcframework" else {
            throw CLIError(
                message: "refusing to delete '\(outputURL.path)': not an .xcframework bundle",
                exitCode: 1
            )
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
    }

    /// 创建与输出同卷的私有暂存目录（优先 itemReplacementDirectory，便于最终 move 不跨卷），
    /// 失败时退回系统临时目录。调用方负责在结束后删除。
    private static func makeStagingDirectory(near outputURL: URL) throws -> URL {
        let fileManager = FileManager.default
        if let replacementDirectoryURL = try? fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: outputURL.deletingLastPathComponent(),
            create: true
        ) {
            return replacementDirectoryURL
        }
        let fallbackURL = fileManager.temporaryDirectory
            .appendingPathComponent("machoe-cli-xcframework-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: fallbackURL, withIntermediateDirectories: true)
        return fallbackURL
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
        // Drain the pipe before waiting: a child that fills the pipe buffer would otherwise
        // block forever while we block in waitUntilExit (stdout and stderr share this pipe).
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

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

    private static func runAdvancedBuild(_ parsed: CLIParsedArguments) throws -> String {
        guard parsed.positionals.isEmpty else {
            throw CLIError.invalidUsage(usage, detail: "unexpected argument '\(parsed.positionals[0])'")
        }
        let sourceLibraryURL = URL(filePath: try parsed.requiredValue("--source-library", usage: usage))
        let deviceLibraryURL = parsed.value("--ios-device-source-library").map { URL(filePath: $0) }
        let simulatorLibraryURL = parsed.value("--ios-simulator-source-library").map { URL(filePath: $0) }
        let macCatalystLibraryURL = parsed.value("--maccatalyst-source-library").map { URL(filePath: $0) }
        let headersDirectoryURL = URL(filePath: try parsed.requiredValue("--headers-dir", usage: usage))

        let finalOutputURL: URL
        if let explicitOutput = parsed.value("--output") {
            // `--output` 与 `--output-dir` / `--xcframework-name` 互斥；以前会静默忽略后两者，
            // 用户可能以为产物写到了 `--output-dir` 下。
            if parsed.contains("--output-dir") || parsed.contains("--xcframework-name") {
                throw CLIError.invalidUsage(
                    usage,
                    detail: "--output cannot be combined with --output-dir or --xcframework-name"
                )
            }
            finalOutputURL = try validatedXCFrameworkOutputURL(explicitOutput)
        } else {
            let outputDirectoryURL = URL(filePath: try parsed.requiredValue("--output-dir", usage: usage))
            let xcframeworkName = parsed.value("--xcframework-name") ?? "SDK.xcframework"
            guard isValidXCFrameworkName(xcframeworkName) else {
                throw CLIError.invalidUsage(
                    usage,
                    detail: "--xcframework-name must be a plain name ending in .xcframework (got '\(xcframeworkName)')"
                )
            }
            finalOutputURL = outputDirectoryURL.appendingPathComponent(xcframeworkName, isDirectory: true).standardizedFileURL
        }

        let fileManager = FileManager.default
        try createParentDirectoryIfNeeded(for: finalOutputURL)

        // The build tool creates scratch directories (artifacts, prepared headers) next to the
        // xcframework and deletes them first. Run it inside a private staging directory on the
        // same volume so it can never touch existing user content, then move the result into place.
        let stagingDirectoryURL = try makeStagingDirectory(near: finalOutputURL)
        defer {
            try? fileManager.removeItem(at: stagingDirectoryURL)
        }

        let request = XCFrameworkBuildRequest(
            sourceLibraryURL: sourceLibraryURL,
            iosDeviceSourceLibraryURL: deviceLibraryURL,
            iosSimulatorSourceLibraryURL: simulatorLibraryURL,
            macCatalystSourceLibraryURL: macCatalystLibraryURL,
            headersDirectoryURL: headersDirectoryURL,
            outputDirectoryURL: stagingDirectoryURL,
            outputLibraryName: parsed.value("--output-library-name") ?? "libSDK.a",
            xcframeworkName: finalOutputURL.lastPathComponent,
            moduleName: parsed.value("--module-name"),
            umbrellaHeader: parsed.value("--umbrella-header"),
            macCatalystMinimumVersion: parsed.value("--maccatalyst-min-version") ?? "13.1",
            macCatalystSDKVersion: parsed.value("--maccatalyst-sdk-version") ?? "17.5"
        )

        let outputCollector = CLIXCFrameworkOutputCollector()
        let stagedOutputURL = try XCFrameworkBuildTool().build(request: request) { chunk in
            outputCollector.append(chunk)
        }

        try removeExistingXCFramework(at: finalOutputURL)
        try fileManager.moveItem(at: stagedOutputURL, to: finalOutputURL)

        var lines = ["XCFramework output: \(finalOutputURL.path)"]
        let trimmedOutput = outputCollector.value
            .replacingOccurrences(of: stagingDirectoryURL.path, with: finalOutputURL.deletingLastPathComponent().path)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

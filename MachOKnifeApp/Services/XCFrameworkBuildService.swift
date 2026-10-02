import Foundation
import MachOKnifeKit

struct XCFrameworkBuildConfiguration {
    let sourceLibraryURL: URL
    let iosDeviceSourceLibraryURL: URL?
    let iosSimulatorSourceLibraryURL: URL?
    let macCatalystSourceLibraryURL: URL?
    let headersDirectoryURL: URL
    let outputDirectoryURL: URL
    let outputLibraryName: String
    let xcframeworkName: String
    let moduleName: String?
    let umbrellaHeader: String?
    let macCatalystMinimumVersion: String
    let macCatalystSDKVersion: String
}

/// Typed failures from the XCFramework build. User-facing text is produced by the window
/// controller through `L10n` so it follows the current app language.
nonisolated enum XCFrameworkBuildError: Error, Equatable {
    case cancelled
    case invalidXCFrameworkName(String)
    case missingOutputPath
    case failed(output: String)
    case developerToolNotFound(String)
    case developerDirectoryUnavailable
}

final class XCFrameworkBuildService {
    private var process: Process?
    private var session: BuildSession?
    private let fileManager: FileManager
    private let toolLocator: XCFrameworkDeveloperToolLocator

    init(fileManager: FileManager = .default, toolLocator: XCFrameworkDeveloperToolLocator = .init()) {
        self.fileManager = fileManager
        self.toolLocator = toolLocator
    }

    var isRunning: Bool {
        process?.isRunning == true
    }

    /// Cancels the running build. The build script makes itself a process-group leader, so the
    /// signal is delivered to the whole group (python and any xcodebuild/libtool/lipo children).
    func cancel() {
        guard let process, let session else { return }
        session.markCancelled()
        if process.isRunning {
            let pid = process.processIdentifier
            if killpg(pid, SIGTERM) != 0 {
                process.terminate()
            }
        }
        self.process = nil
        self.session = nil
    }

    /// Trims a user-entered name and appends `.xcframework` when the extension is missing.
    static func normalizedXCFrameworkName(_ rawValue: String, defaultName: String = "SDK.xcframework") -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return defaultName
        }
        if (trimmed as NSString).pathExtension.lowercased() == "xcframework" {
            return trimmed
        }
        return trimmed + ".xcframework"
    }

    static func isValidXCFrameworkName(_ name: String) -> Bool {
        guard name.contains("/") == false,
              name.hasPrefix(".") == false,
              name.count > ".xcframework".count,
              (name as NSString).pathExtension == "xcframework" else {
            return false
        }
        return true
    }

    /// Starts a build. `outputHandler` and `completionHandler` are always invoked on the main queue.
    func startBuild(
        configuration: XCFrameworkBuildConfiguration,
        outputHandler: @escaping @MainActor (String) -> Void,
        completionHandler: @escaping @MainActor (Result<URL, Error>) -> Void
    ) throws {
        cancel()

        guard Self.isValidXCFrameworkName(configuration.xcframeworkName) else {
            throw XCFrameworkBuildError.invalidXCFrameworkName(configuration.xcframeworkName)
        }

        let environment = try makeEnvironment()
        let scriptURL = try writeScript()
        let scriptDirectoryURL = scriptURL.deletingLastPathComponent()
        let removeScript: @Sendable () -> Void = { try? FileManager.default.removeItem(at: scriptDirectoryURL) }
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = makeArguments(scriptURL: scriptURL, configuration: configuration)
        process.environment = environment
        process.standardOutput = stdout
        process.standardError = stderr

        let session = BuildSession()
        let outputCollector = OutputCollector()
        let appendOutput: @Sendable (Data) -> Void = { data in
            let text = String(decoding: data, as: UTF8.self)
            guard text.isEmpty == false else { return }
            outputCollector.append(text)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    outputHandler(text)
                }
            }
        }

        do {
            try process.run()
        } catch {
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForWriting.close()
            removeScript()
            throw error
        }
        self.process = process
        self.session = session

        // Each pipe is drained on its own thread until EOF, so output is delivered exactly once
        // and in order; completion is reported only after both streams are fully read.
        let readers = DispatchGroup()
        for pipe in [stdout, stderr] {
            readers.enter()
            let handle = pipe.fileHandleForReading
            DispatchQueue.global(qos: .userInitiated).async {
                while true {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    appendOutput(data)
                }
                readers.leave()
            }
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            readers.wait()
            process.waitUntilExit()
            removeScript()

            let result = Self.makeResult(
                process: process,
                output: outputCollector.value,
                wasCancelled: session.isCancelled
            )

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if self?.process === process {
                        self?.process = nil
                        self?.session = nil
                    }
                    completionHandler(result)
                }
            }
        }
    }

    nonisolated private static func makeResult(process: Process, output: String, wasCancelled: Bool) -> Result<URL, Error> {
        if wasCancelled {
            return .failure(XCFrameworkBuildError.cancelled)
        }

        if process.terminationReason == .exit, process.terminationStatus == 0 {
            let outputPath = output
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .last { $0.hasSuffix(".xcframework") }
                .map { URL(fileURLWithPath: $0) }

            if let outputPath {
                return .success(outputPath)
            }
            return .failure(XCFrameworkBuildError.missingOutputPath)
        }

        return .failure(XCFrameworkBuildError.failed(output: output.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    private func makeArguments(scriptURL: URL, configuration: XCFrameworkBuildConfiguration) -> [String] {
        var arguments = [scriptURL.path]
        arguments += ["--source-library", configuration.sourceLibraryURL.path]
        if let iosDeviceSourceLibraryURL = configuration.iosDeviceSourceLibraryURL {
            arguments += ["--ios-device-source-library", iosDeviceSourceLibraryURL.path]
        }
        if let iosSimulatorSourceLibraryURL = configuration.iosSimulatorSourceLibraryURL {
            arguments += ["--ios-simulator-source-library", iosSimulatorSourceLibraryURL.path]
        }
        if let macCatalystSourceLibraryURL = configuration.macCatalystSourceLibraryURL {
            arguments += ["--maccatalyst-source-library", macCatalystSourceLibraryURL.path]
        }
        arguments += ["--headers-dir", configuration.headersDirectoryURL.path]
        arguments += ["--output-dir", configuration.outputDirectoryURL.path]
        arguments += ["--output-library-name", configuration.outputLibraryName]
        arguments += ["--xcframework-name", configuration.xcframeworkName]
        arguments += ["--maccatalyst-min-version", configuration.macCatalystMinimumVersion]
        arguments += ["--maccatalyst-sdk-version", configuration.macCatalystSDKVersion]
        if let moduleName = configuration.moduleName, moduleName.isEmpty == false {
            arguments += ["--module-name", moduleName]
        }
        if let umbrellaHeader = configuration.umbrellaHeader, umbrellaHeader.isEmpty == false {
            arguments += ["--umbrella-header", umbrellaHeader]
        }
        return arguments
    }

    private func makeEnvironment() throws -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["MACHOKNIFE_OWN_PROCESS_GROUP"] = "1"
        // Resolve the developer roots once (this runs `xcode-select -p`) and reuse them for every tool.
        let resolution = toolLocator.resolve()
        environment["MACHOKNIFE_LIPO"] = try resolution.path(named: "lipo")
        environment["MACHOKNIFE_LIBTOOL"] = try resolution.path(named: "libtool")
        environment["MACHOKNIFE_AR"] = try resolution.path(named: "ar")
        environment["MACHOKNIFE_XCODEBUILD"] = try resolution.path(named: "xcodebuild")
        if let developerDirectory = resolution.selectedDeveloperDirectory {
            environment["DEVELOPER_DIR"] = developerDirectory.path
        }
        return environment
    }

    private func writeScript() throws -> URL {
        // A unique directory per build keeps concurrent builds from overwriting each other's script.
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("machoknife-xcframework-builder-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent("build_static_sdk_xcframework.py")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        return scriptURL
    }

    /// Single source of truth for the build steps; the app adds cancellation around it.
    private var script: String { XCFrameworkBuildTool.scriptSource }
}

private final class BuildSession: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var cancelled = false

    nonisolated func markCancelled() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    nonisolated var isCancelled: Bool {
        lock.lock()
        let value = cancelled
        lock.unlock()
        return value
    }
}

private final class OutputCollector: @unchecked Sendable {
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

struct XCFrameworkDeveloperToolLocator {
    /// Developer roots resolved once, used to look up several tools without re-running `xcode-select`.
    struct Resolution {
        let developerRoots: [URL]
        let selectedDeveloperDirectory: URL?

        func path(named tool: String) throws -> String {
            let toolchainRelativePath = "Toolchains/XcodeDefault.xctoolchain/usr/bin/\(tool)"
            let developerRelativePath = "usr/bin/\(tool)"
            let candidates = developerRoots.flatMap { root in
                [
                    root.appendingPathComponent(toolchainRelativePath).path,
                    root.appendingPathComponent(developerRelativePath).path,
                ]
            } + ["/usr/bin/\(tool)", "/bin/\(tool)"]

            if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                return path
            }
            throw XCFrameworkBuildError.developerToolNotFound(tool)
        }
    }

    func resolve() -> Resolution {
        let selected = try? selectedDeveloperDirectory()
        return Resolution(
            developerRoots: preferredDeveloperRoots(selected: selected),
            selectedDeveloperDirectory: selected
        )
    }

    func path(named tool: String) throws -> String {
        try resolve().path(named: tool)
    }

    func selectedDeveloperDirectory() throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        try process.run()
        // Read before waiting so a full pipe can never block the child.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw XCFrameworkBuildError.developerDirectoryUnavailable
        }

        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.isEmpty == false else {
            throw XCFrameworkBuildError.developerDirectoryUnavailable
        }
        return URL(fileURLWithPath: output, isDirectory: true)
    }

    private func preferredDeveloperRoots(selected: URL?) -> [URL] {
        var roots = [URL]()
        if
            let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"],
            developerDir.isEmpty == false
        {
            roots.append(URL(fileURLWithPath: developerDir, isDirectory: true))
        }
        if let selected {
            roots.append(selected)
        }
        roots.append(URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer", isDirectory: true))

        return roots.reduce(into: [URL]()) { result, root in
            guard FileManager.default.fileExists(atPath: root.path) else { return }
            if result.contains(root) == false {
                result.append(root)
            }
        }
    }
}

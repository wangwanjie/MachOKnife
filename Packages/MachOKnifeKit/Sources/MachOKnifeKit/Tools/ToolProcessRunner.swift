import Foundation

/// Result of a finished child process with its fully drained output streams.
struct ToolProcessResult: Sendable {
    let terminationStatus: Int32
    let terminationReason: Process.TerminationReason
    let standardOutput: Data
    let standardError: Data

    var succeeded: Bool {
        terminationReason == .exit && terminationStatus == 0
    }

    var combinedOutputText: String {
        String(decoding: standardOutput + standardError, as: UTF8.self)
    }
}

/// Runs a child process while draining stdout and stderr concurrently.
///
/// Reading the pipes only after `waitUntilExit()` deadlocks as soon as a child writes more
/// than the pipe buffer (64 KiB) to either stream, because the child blocks on `write` while
/// the parent blocks waiting for it to exit.
enum ToolProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil
    ) throws -> ToolProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        if let currentDirectoryURL {
            process.currentDirectoryURL = currentDirectoryURL
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let errorBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        return ToolProcessResult(
            terminationStatus: process.terminationStatus,
            terminationReason: process.terminationReason,
            standardOutput: outputData,
            standardError: errorBox.data
        )
    }
}

/// Written by exactly one background reader before `DispatchGroup.wait()` returns.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}

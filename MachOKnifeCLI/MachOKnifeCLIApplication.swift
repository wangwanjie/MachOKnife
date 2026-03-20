import Foundation
import MachOKnifeKit

enum MachOKnifeCLIApplication {
    static func main(arguments: [String] = CommandLine.arguments) {
        do {
            let output = try run(arguments: arguments)
            FileHandle.standardOutput.write(Data(output.utf8))
        } catch let error as CLIError {
            FileHandle.standardError.write(Data("error: \(error.message)\n".utf8))
            Foundation.exit(Int32(error.exitCode))
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    static func run(arguments: [String]) throws -> String {
        guard arguments.count >= 3 else {
            throw CLIError.usage
        }

        let command = arguments[1]
        let url = URL(filePath: arguments[2])
        let service = DocumentAnalysisService()
        let analysis = try service.analyze(url: url)

        switch command {
        case "info":
            return CLIReportRenderer.renderInfo(analysis)
        case "list-dylibs":
            return CLIReportRenderer.renderDylibs(analysis)
        default:
            throw CLIError.unsupportedCommand(command)
        }
    }
}

struct CLIError: Error {
    let message: String
    let exitCode: Int

    static let usage = CLIError(
        message: """
        usage:
          machoe-cli info <path>
          machoe-cli list-dylibs <path>
        """,
        exitCode: 1
    )

    static func unsupportedCommand(_ command: String) -> CLIError {
        CLIError(message: "unsupported command '\(command)'", exitCode: 2)
    }
}

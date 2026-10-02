import Foundation
import Testing
@testable import MachOKnifeKit

/// Debug helper: `LAYOUT_DUMP_INPUT=/path LAYOUT_DUMP_OUTPUT=/tmp/out.txt swift test --filter LayoutDumpTests`.
@Suite struct LayoutDumpTests {
    @Test func dumpWhenRequested() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let input = environment["LAYOUT_DUMP_INPUT"], let output = environment["LAYOUT_DUMP_OUTPUT"] else { return }
        let maxRows = Int(environment["LAYOUT_DUMP_ROWS"] ?? "") ?? 40
        let document = try BrowserDocumentService().load(url: URL(fileURLWithPath: input))
        var text = ""
        func visit(_ node: BrowserNode, depth: Int) {
            let indent = String(repeating: "  ", count: depth)
            text += "\(indent)# \(node.title) [\(node.subtitle ?? "")] raw=\(node.rawAddress.map { String($0, radix: 16) } ?? "-") rva=\(node.rvaAddress.map { String($0, radix: 16) } ?? "-") rows=\(node.detailCount) children=\(node.childCount)\n"
            for index in 0..<min(node.detailCount, maxRows) {
                let row = node.detailRow(at: index)
                text += "\(indent)  | \(row.rawAddress.map { String($0, radix: 16) } ?? "") | \(row.dataPreview ?? "") | \(row.key) | \(row.value)\n"
            }
            for index in 0..<min(node.childCount, 60) {
                visit(node.child(at: index), depth: depth + 1)
            }
        }
        for root in document.rootNodes {
            visit(root, depth: 0)
        }
        try text.write(toFile: output, atomically: true, encoding: .utf8)
    }
}

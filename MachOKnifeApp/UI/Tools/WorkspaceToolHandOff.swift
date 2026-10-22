import Foundation

/// 决定工具窗口打开时是否用主工作区当前打开的文件预填输入。
///
/// 规则：
/// - 工具当前没有输入：直接使用工作区文件；
/// - 工具当前输入正是工作区文件：无需重复载入；
/// - 工具当前输入是上次由工作区交接过来的文件（用户没有手动更换）：跟随工作区切换到新文件；
/// - 用户在工具里手动选择了别的文件：保留用户的选择，不覆盖。
struct WorkspaceToolHandOff {
    /// 最近一次由工作区交接给工具的文件。
    private(set) var lastHandedOffURL: URL?

    /// 返回需要载入到工具中的文件；返回 `nil` 表示保持工具当前输入不变。
    /// 返回非空值时会同时记录这次交接。
    mutating func inputToPrefill(workspaceDocumentURL: URL?, currentInputURL: URL?) -> URL? {
        guard let workspaceDocumentURL else {
            return nil
        }

        guard let currentInputURL else {
            lastHandedOffURL = workspaceDocumentURL
            return workspaceDocumentURL
        }

        if Self.isSameFile(currentInputURL, workspaceDocumentURL) {
            return nil
        }

        if let lastHandedOffURL, Self.isSameFile(currentInputURL, lastHandedOffURL) {
            self.lastHandedOffURL = workspaceDocumentURL
            return workspaceDocumentURL
        }

        return nil
    }

    private static func isSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }
}

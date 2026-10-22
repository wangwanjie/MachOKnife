import Foundation
import MachOKnifeKit

/// “移除架构”表单的状态与操作：选择通用（fat）二进制或 fat 静态库，勾选要移除的架构，
/// 选择输出文件后在后台调用 `MachOMergeSplitService.removeArchitectures`。
@MainActor
final class RemoveArchitecturesViewModel {
    enum Status {
        case idle
        case running
        case completed(URL)
        case failed(Error)
    }

    /// 读取输入文件包含的架构列表。
    typealias ArchitecturesProvider = (URL) throws -> [String]
    /// 执行移除操作：参数依次为要移除的架构、输入文件、输出文件。会在后台线程上调用。
    typealias ArchitectureRemover = @Sendable ([String], URL, URL) throws -> Void

    private(set) var inputURL: URL?
    private(set) var availableArchitectures: [String] = []
    private(set) var architecturesToRemove: Set<String> = []
    private(set) var outputURL: URL?
    private(set) var status: Status = .idle
    /// 状态变化时回调，供视图控制器刷新界面。
    var onChange: (() -> Void)?

    private let architecturesProvider: ArchitecturesProvider
    private let architectureRemover: ArchitectureRemover
    /// 正在进行的操作 ID；为 nil 表示空闲。用于丢弃已被取代的旧结果。
    private var activeOperationID: UUID?

    init(
        architecturesProvider: @escaping ArchitecturesProvider = { url in
            try MachOMergeSplitService().availableArchitectures(for: url)
        },
        architectureRemover: @escaping ArchitectureRemover = { architectures, inputURL, outputURL in
            try MachOMergeSplitService().removeArchitectures(architectures, from: inputURL, outputURL: outputURL)
        }
    ) {
        self.architecturesProvider = architecturesProvider
        self.architectureRemover = architectureRemover
    }

    var isRunning: Bool {
        activeOperationID != nil
    }

    /// 按可用架构的顺序返回已勾选的架构，保证传给服务的参数顺序稳定。
    var orderedArchitecturesToRemove: [String] {
        availableArchitectures.filter { architecturesToRemove.contains($0) }
    }

    /// 输入只有一个架构时没有可移除的内容。
    var hasRemovableArchitectures: Bool {
        availableArchitectures.count >= 2
    }

    /// 是否勾选了全部架构（移除后将一个不剩，服务会拒绝）。
    var removesEveryArchitecture: Bool {
        availableArchitectures.isEmpty == false
            && availableArchitectures.allSatisfy { architecturesToRemove.contains($0) }
    }

    var canStart: Bool {
        guard isRunning == false, inputURL != nil, outputURL != nil else {
            return false
        }
        guard hasRemovableArchitectures else {
            return false
        }
        return architecturesToRemove.isEmpty == false && removesEveryArchitecture == false
    }

    /// 输出文件的默认名称：在原文件名后追加 “-thin”，保留扩展名。
    var suggestedOutputFileName: String {
        guard let inputURL else {
            return "Output"
        }
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let pathExtension = inputURL.pathExtension
        if pathExtension.isEmpty {
            return "\(baseName)-thin"
        }
        return "\(baseName)-thin.\(pathExtension)"
    }

    /// 载入输入文件并读取其架构列表。读取失败时清空架构并把错误抛给调用方展示。
    func loadInput(_ url: URL) throws {
        guard isRunning == false else {
            return
        }
        inputURL = url
        architecturesToRemove = []
        // 输出文件以输入文件命名，换了输入后旧的输出路径不再适用。
        outputURL = nil
        status = .idle
        do {
            availableArchitectures = try architecturesProvider(url)
            notifyChange()
        } catch {
            availableArchitectures = []
            notifyChange()
            throw error
        }
    }

    func clearInput() {
        guard isRunning == false else {
            return
        }
        inputURL = nil
        availableArchitectures = []
        architecturesToRemove = []
        outputURL = nil
        status = .idle
        notifyChange()
    }

    func setArchitecture(_ architecture: String, removed: Bool) {
        guard isRunning == false, availableArchitectures.contains(architecture) else {
            return
        }
        if removed {
            architecturesToRemove.insert(architecture)
        } else {
            architecturesToRemove.remove(architecture)
        }
        resetStatusAfterEdit()
    }

    func setOutputURL(_ url: URL?) {
        guard isRunning == false else {
            return
        }
        outputURL = url
        resetStatusAfterEdit()
    }

    /// 在后台执行移除操作。返回的任务供测试等待完成；条件不满足时返回 nil。
    @discardableResult
    func start() -> Task<Void, Never>? {
        guard canStart, let inputURL, let outputURL else {
            return nil
        }
        let architectures = orderedArchitecturesToRemove
        let remover = architectureRemover
        let operationID = UUID()
        activeOperationID = operationID
        status = .running
        notifyChange()

        // lipo 需要复制整个二进制，放到后台执行，避免阻塞主线程。
        let worker = Task.detached(priority: .userInitiated) {
            Result<Void, Error> {
                try remover(architectures, inputURL, outputURL)
            }
        }
        return Task { [weak self] in
            let result = await worker.value
            self?.finish(result, operationID: operationID, outputURL: outputURL)
        }
    }

    private func finish(_ result: Result<Void, Error>, operationID: UUID, outputURL: URL) {
        guard activeOperationID == operationID else {
            return
        }
        activeOperationID = nil
        switch result {
        case .success:
            status = .completed(outputURL)
        case let .failure(error):
            status = .failed(error)
        }
        notifyChange()
    }

    /// 修改了表单内容后，之前的“完成/失败”状态不再适用。
    private func resetStatusAfterEdit() {
        if isRunning == false {
            status = .idle
        }
        notifyChange()
    }

    private func notifyChange() {
        onChange?()
    }
}

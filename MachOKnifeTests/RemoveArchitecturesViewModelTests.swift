import Foundation
import MachOKnifeKit
import Testing
@testable import MachOKnife

/// “移除架构”表单视图模型的测试。
@MainActor
struct RemoveArchitecturesViewModelTests {
    @Test("loading an input lists its architectures and resets selection and output")
    func loadingInputListsArchitectures() throws {
        let viewModel = RemoveArchitecturesViewModel(
            architecturesProvider: { _ in ["arm64", "x86_64"] },
            architectureRemover: { _, _, _ in }
        )
        var changeCount = 0
        viewModel.onChange = {
            changeCount += 1
        }
        let inputURL = URL(filePath: "/tmp/remove/libFat.a")

        try viewModel.loadInput(inputURL)
        viewModel.setArchitecture("x86_64", removed: true)
        viewModel.setOutputURL(URL(filePath: "/tmp/remove/out.a"))

        #expect(viewModel.inputURL == inputURL)
        #expect(viewModel.availableArchitectures == ["arm64", "x86_64"])
        #expect(viewModel.architecturesToRemove == ["x86_64"])
        #expect(viewModel.canStart)
        #expect(viewModel.suggestedOutputFileName == "libFat-thin.a")
        #expect(changeCount == 3)

        // 换一个输入：勾选和输出路径都要清空。
        try viewModel.loadInput(URL(filePath: "/tmp/remove/Other"))
        #expect(viewModel.architecturesToRemove.isEmpty)
        #expect(viewModel.outputURL == nil)
        #expect(viewModel.suggestedOutputFileName == "Other-thin")
        #expect(viewModel.canStart == false)
    }

    @Test("start requires a partial architecture selection and an output")
    func startRequiresValidSelection() throws {
        let viewModel = RemoveArchitecturesViewModel(
            architecturesProvider: { _ in ["arm64", "x86_64"] },
            architectureRemover: { _, _, _ in }
        )
        #expect(viewModel.canStart == false)

        try viewModel.loadInput(URL(filePath: "/tmp/remove/libFat.a"))
        viewModel.setOutputURL(URL(filePath: "/tmp/remove/out.a"))
        // 没有勾选任何架构。
        #expect(viewModel.canStart == false)

        viewModel.setArchitecture("arm64", removed: true)
        viewModel.setArchitecture("x86_64", removed: true)
        // 全部勾选：移除后一个不剩。
        #expect(viewModel.removesEveryArchitecture)
        #expect(viewModel.canStart == false)
        #expect(viewModel.start() == nil)

        viewModel.setArchitecture("arm64", removed: false)
        #expect(viewModel.canStart)

        // 不在列表中的架构会被忽略。
        viewModel.setArchitecture("i386", removed: true)
        #expect(viewModel.architecturesToRemove == ["x86_64"])
    }

    @Test("a single-architecture input has nothing to remove")
    func singleArchitectureInputCannotStart() throws {
        let viewModel = RemoveArchitecturesViewModel(
            architecturesProvider: { _ in ["arm64"] },
            architectureRemover: { _, _, _ in }
        )

        try viewModel.loadInput(URL(filePath: "/tmp/remove/libThin.dylib"))
        viewModel.setOutputURL(URL(filePath: "/tmp/remove/out.dylib"))

        #expect(viewModel.hasRemovableArchitectures == false)
        #expect(viewModel.canStart == false)
    }

    @Test("a failing architecture lookup clears the architecture list and rethrows")
    func failingLookupClearsArchitectures() {
        struct LookupFailure: Error {}
        let viewModel = RemoveArchitecturesViewModel(
            architecturesProvider: { _ in
                throw LookupFailure()
            },
            architectureRemover: { _, _, _ in }
        )

        #expect(throws: LookupFailure.self) {
            try viewModel.loadInput(URL(filePath: "/tmp/remove/broken"))
        }
        #expect(viewModel.inputURL == URL(filePath: "/tmp/remove/broken"))
        #expect(viewModel.availableArchitectures.isEmpty)
        #expect(viewModel.canStart == false)
    }

    @Test("start runs the removal off the main thread and reports completion")
    func startRunsRemovalInBackground() async throws {
        let recorder = RemovalRecorder()
        let viewModel = RemoveArchitecturesViewModel(
            architecturesProvider: { _ in ["arm64", "arm64e", "x86_64"] },
            architectureRemover: { architectures, inputURL, outputURL in
                recorder.record(architectures: architectures, inputURL: inputURL, outputURL: outputURL, isMainThread: Thread.isMainThread)
            }
        )
        let inputURL = URL(filePath: "/tmp/remove/libFat.a")
        let outputURL = URL(filePath: "/tmp/remove/out.a")
        try viewModel.loadInput(inputURL)
        // 勾选顺序与列表顺序不同，传给服务时应按列表顺序排列。
        viewModel.setArchitecture("x86_64", removed: true)
        viewModel.setArchitecture("arm64e", removed: true)
        viewModel.setOutputURL(outputURL)

        let task = try #require(viewModel.start())
        #expect(viewModel.isRunning)
        guard case .running = viewModel.status else {
            Issue.record("start 之后应处于 running 状态")
            return
        }
        // 运行期间表单不可修改，也不能重复开始。
        viewModel.setArchitecture("arm64", removed: true)
        #expect(viewModel.architecturesToRemove == ["x86_64", "arm64e"])
        #expect(viewModel.start() == nil)

        await task.value

        #expect(viewModel.isRunning == false)
        guard case let .completed(completedURL) = viewModel.status else {
            Issue.record("完成后应处于 completed 状态，实际为 \(viewModel.status)")
            return
        }
        #expect(completedURL == outputURL)
        let call = try #require(recorder.calls.first)
        #expect(recorder.calls.count == 1)
        #expect(call.architectures == ["arm64e", "x86_64"])
        #expect(call.inputURL == inputURL)
        #expect(call.outputURL == outputURL)
        #expect(call.isMainThread == false)
    }

    @Test("a failing removal surfaces the error in the status")
    func failingRemovalReportsError() async throws {
        let viewModel = RemoveArchitecturesViewModel(
            architecturesProvider: { _ in ["arm64", "x86_64"] },
            architectureRemover: { _, inputURL, _ in
                throw MachOToolServiceError.notUniversal(inputURL)
            }
        )
        try viewModel.loadInput(URL(filePath: "/tmp/remove/libFat.a"))
        viewModel.setArchitecture("x86_64", removed: true)
        viewModel.setOutputURL(URL(filePath: "/tmp/remove/out.a"))

        let task = try #require(viewModel.start())
        await task.value

        guard case let .failed(error) = viewModel.status else {
            Issue.record("失败后应处于 failed 状态，实际为 \(viewModel.status)")
            return
        }
        #expect(error is MachOToolServiceError)
        // 修改表单后状态回到 idle。
        viewModel.setArchitecture("x86_64", removed: false)
        guard case .idle = viewModel.status else {
            Issue.record("修改表单后应回到 idle 状态")
            return
        }
    }

    @Test("removing an architecture from a real universal dylib writes a thinner binary")
    func removesArchitectureFromRealUniversalBinary() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let universalURL = try makeUniversalDylib(in: directory)
        let outputURL = directory.appendingPathComponent("libUniversal-thin.dylib")
        let viewModel = RemoveArchitecturesViewModel()

        try viewModel.loadInput(universalURL)
        #expect(Set(viewModel.availableArchitectures) == ["arm64", "x86_64"])
        viewModel.setArchitecture("x86_64", removed: true)
        viewModel.setOutputURL(outputURL)

        let task = try #require(viewModel.start())
        await task.value

        guard case .completed = viewModel.status else {
            Issue.record("真实移除应成功，实际为 \(viewModel.status)")
            return
        }
        let remaining = try MachOMergeSplitService().availableArchitectures(for: outputURL)
        #expect(remaining == ["arm64"])
    }

    // MARK: - Helpers

    private func makeUniversalDylib(in directory: URL) throws -> URL {
        let sourceURL = directory.appendingPathComponent("universal.c")
        let outputURL = directory.appendingPathComponent("libUniversal.dylib")
        try "int machoknife_remove_arch_fixture(void) { return 3; }\n"
            .write(to: sourceURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/clang")
        process.arguments = [
            "-arch", "arm64",
            "-arch", "x86_64",
            "-dynamiclib",
            sourceURL.path,
            "-o", outputURL.path,
        ]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return outputURL
    }
}

/// 在后台线程记录移除调用的参数（线程安全）。
private final class RemovalRecorder: @unchecked Sendable {
    struct Call {
        let architectures: [String]
        let inputURL: URL
        let outputURL: URL
        let isMainThread: Bool
    }

    private let lock = NSLock()
    private var storage: [Call] = []

    func record(architectures: [String], inputURL: URL, outputURL: URL, isMainThread: Bool) {
        lock.lock()
        storage.append(Call(architectures: architectures, inputURL: inputURL, outputURL: outputURL, isMainThread: isMainThread))
        lock.unlock()
    }

    var calls: [Call] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return storage
    }
}

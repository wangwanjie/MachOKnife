## Why

MachOKnife 在打开大型 Mach-O 时会明显卡顿，严重时整个 app 失去响应。现有工作区打开链路会在主线程同步执行完整浏览模型构建和完整摘要分析，对类似 `/Users/VanJay/Documents/Career/ReverseAndJailBreak/脱壳应用/11ProMax-16.5/酷狗音乐_12.3.2/kugou` 这类 301MB 的 arm64 Mach-O，放大了 UI 阻塞、内存占用和超大集合渲染问题。

## What Changes

- 将工作区文档打开与重分析改为分阶段、后台执行，避免主线程被完整解析流程阻塞。
- 将大型 Mach-O 的重数据集合改为按需加载，而不是在首次打开时一次性解析并建模全部符号、字符串表、导出/绑定信息。
- 为超大文件和超高基数集合增加性能保护策略，包括大文件识别、延迟加载入口、分页/批量呈现、必要时的降级展示。
- 增加覆盖大型二进制场景的性能回归验证，确保后续变更不会重新引入“打开即卡死”的行为。

## Capabilities

### New Capabilities
- `workspace-responsive-loading`: 工作区在打开或重分析大型 Mach-O 时必须保持界面可交互，并向用户展示明确的加载进度、阶段状态和失败信息。
- `workspace-on-demand-analysis`: 工作区必须对符号、字符串表、绑定/导出信息等高成本数据执行按需分析与受限呈现，避免首次打开时做全量解析和全量 UI 构建。

### Modified Capabilities
- None.

## Impact

- 受影响代码主要位于 `MachOKnifeApp/ViewModels/WorkspaceViewModel.swift`、`MachOKnifeApp/UI/Workspace/`、`Packages/MachOKnifeKit/Sources/MachOKnifeKit/Browser/BrowserDocumentService.swift`、`Packages/MachOKnifeKit/Sources/MachOKnifeKit/MachOKnifeKit.swift`、`Packages/CoreMachO/Sources/CoreMachO/CoreMachO.swift`。
- 需要补充大型 Mach-O 加载、懒分析、分页展示和性能门槛相关测试。
- 不引入外部 API breaking change，但会调整工作区内部加载时序、数据模型和部分 UI 交互。

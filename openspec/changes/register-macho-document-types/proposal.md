## Why

MachOKnife 已经具备从 Finder 传入路径后打开 Mach-O 的能力，但 app bundle 还没有正式声明 Mach-O 相关文档类型，因此不会稳定出现在 Finder 的“打开方式”候选里。现在补齐这层 Launch Services 注册，可以让用户从系统入口直接把 MachOKnife 作为 Mach-O 检查器使用，而不必先启动 app 再手动选择文件。

## What Changes

- 为 MachOKnife 增加一组面向 Mach-O、fat Mach-O 和静态库 archive 的文档类型声明，使 app 能作为这些内容类型的 Finder `Open With` 候选应用。
- 以内容类型识别为主、常见扩展名为辅建模文档类型，覆盖 thin/fat Mach-O、常见动态库与静态库场景，并将无后缀裸 Mach-O 可执行文件定义为“按系统识别结果尽力支持”。
- 明确 MachOKnife 的文档角色为查看/分析，不声明对 `.app`、`.framework`、`.appex` 等 bundle 本体的打开方式支持。
- 补充针对 Finder 集成与应用打开链路的验证，确保 Launch Services 注册与现有 `application(_:openFiles:)` 行为一致。

## Capabilities

### New Capabilities
- `macho-document-association`: MachOKnife 作为 Mach-O 相关文件和 archive 的系统级查看器被 Finder 识别，并通过右键“打开方式”与默认打开应用流程调用现有文档打开链路。

### Modified Capabilities
- None.

## Impact

- 受影响代码和配置主要位于 `MachOKnife/Info.plist`、应用 target 的 bundle 元数据，以及与 Finder 打开入口衔接的 `MachOKnifeApp/AppDelegate.swift` / `MachOKnifeApp/UI/MainWindowController.swift` 验证范围。
- 需要新增或更新与文档类型声明、Finder `Open With` 候选出现、默认打开应用切换、无后缀 Mach-O 尽力识别相关的手动验证说明。
- 不引入外部依赖，也不改变现有工作区解析能力；主要变更是系统集成层面的文档类型声明与验证。

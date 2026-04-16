## Context

MachOKnife 当前已经具备完整的文档打开链路：Finder 或系统把文件路径传入应用后，`AppDelegate.application(_:openFiles:)` 会调用主窗口控制器的 `openDocument(at:)` 打开工作区文档。缺失的是 bundle 元数据层面的文档类型声明，导致 Launch Services 无法把 MachOKnife 稳定登记为 Mach-O 相关文件的查看器，用户在 Finder 右键 `Open With` 或切换默认打开应用时看不到它。

这次变更的目标是系统集成，不是解析能力扩展。实现要尽量复用现有打开链路，避免引入 Finder Extension、Quick Action 或新的运行时文件探测守护逻辑。约束条件来自 macOS 自身的内容类型识别能力：对无后缀裸 Mach-O 文件，只能在系统已经能把文件归类到已声明内容类型时提供支持，不能对所有裸二进制做强保证。

## Goals / Non-Goals

**Goals:**

- 让 MachOKnife 作为 thin Mach-O、fat Mach-O、常见动态库和静态库 archive 的 Finder `Open With` 候选应用。
- 通过 Launch Services 文档类型声明，把系统级文件关联接到现有 `application(_:openFiles:)` 打开链路。
- 以内容类型建模为主，使用常见扩展名和文件名约定作为补充，尽可能覆盖无后缀 Mach-O 的系统可识别场景。
- 明确 MachOKnife 是查看/分析器，不把 bundle 本体纳入支持范围。
- 增加手动验证步骤，覆盖 Finder 右键菜单、默认打开应用切换和现有打开链路。

**Non-Goals:**

- 不新增 Finder Extension、Quick Action、Service 菜单或其他额外系统入口。
- 不扩展 MachOKnife 对 `.app`、`.framework`、`.appex` 等 bundle 容器本体的打开方式支持。
- 不修改 Mach-O 解析、工作区建模或文件内容识别算法。
- 不承诺所有无后缀裸可执行文件都一定出现在 `Open With` 列表里。

## Decisions

### 1. 使用 Launch Services 文档类型声明，而不是新增 Finder 集成模块

实现将集中在 app bundle 元数据：

- 在 `MachOKnife/Info.plist` 中增加 `CFBundleDocumentTypes`
- 为这些文档类型补充 `LSItemContentTypes`
- 在需要时增加 `UTImportedTypeDeclarations`，为 Mach-O / fat Mach-O / archive 建立应用侧可引用的导入型类型标识

这样做的原因是需求本质上是“让 Finder 认识这个 app 能打开哪些文件”，而不是“增加一个新的 Finder 功能模块”。相比 Finder Extension 或 Quick Action，文档类型声明更直接、风险更低，也更符合用户确认的范围。

备选方案是只靠扩展名声明 `CFBundleTypeExtensions`。没有采用它，因为这会把关联能力限制在少量已知后缀上，无法表达“按内容类型为主、扩展名为辅”的目标。

### 2. 将支持面拆成三个逻辑组：thin/fat Mach-O、动态库风格文件、静态库 archive

文档类型会按 Finder 侧实际可理解的对象组织，而不是按 MachOKnife 内部解析器模块组织：

- Mach-O 可执行与 object 风格文件
- 动态库风格文件，如 `.dylib`、常见 `.so`
- 静态库 archive，如 `.a`

其中 thin/fat Mach-O 共用一组“Mach-O 家族”关联语义，静态库 archive 单独建模，因为它在 Finder 和 Launch Services 侧通常落在不同类型层级。这样做可以让文档类型描述、验证用例和用户感知保持一致，也能避免把 bundle 容器误并进来。

备选方案是为每一种文件形态都单独声明一个 document type。没有采用它，因为粒度过细会让元数据维护成本和 Launch Services 行为复杂度上升，但不会带来等比例收益。

### 3. 对无后缀裸 Mach-O 采用“系统识别成功时支持”的要求表达

需求中明确选择了“尽力支持”。因此设计上不会尝试通过额外守护进程、文件探测缓存或 Finder 外挂去强行接管所有无后缀可执行文件。规范和验证会写成：

- 当 macOS 已将该文件判定为已声明的 Mach-O 相关内容类型时，MachOKnife 必须作为 `Open With` 候选应用出现。
- 当系统未能判定内容类型时，本次变更不额外承诺 Finder 集成结果。

这样既保留了用户想要的方向，也不对 Launch Services 不提供的能力做虚假保证。

### 4. 文档角色声明为 Viewer，不改动现有打开行为

MachOKnife 的系统角色会被建模为查看/分析，而不是编辑器。原因有两点：

- 产品定位本身是 Mach-O 浏览和工具套件，不是通用二进制编辑器。
- 使用 Viewer 角色能更准确地表达 Finder `Open With` 候选的预期，不会误导系统把 MachOKnife 当作默认编辑器类应用。

运行时行为继续复用现有 `application(_:openFiles:) -> MainWindowController.openDocument(at:)` 链路，不新增专用入口。这样可以把风险控制在 Launch Services 注册和元数据正确性上。

### 5. 把验证分成元数据验证和系统行为验证两层

这次变更真正容易出问题的不是代码分支，而是系统登记效果。因此验证要覆盖两层：

- 元数据层：确认 app bundle 导出的 document types、UTI 和角色声明完整且一致
- 系统行为层：确认 Finder `Open With`、默认打开应用切换和双击/系统打开动作会走到现有文档打开链路

这比只做一次手工右键点击更稳妥，因为 Launch Services 的问题常见于元数据缺失、UTI 关联错误或角色声明不一致。

## Risks / Trade-offs

- [macOS 对无后缀文件的内容类型识别不稳定] -> Mitigation: 在 spec 中明确这是“系统识别成功时支持”，并把手动验证重点放在可重复的样本文件上。
- [自定义或导入型类型声明过多会让 Info.plist 维护变复杂] -> Mitigation: 只保留 Mach-O 家族和静态库 archive 所需的最小集合，不为 bundle 容器或边缘类型过度建模。
- [Finder 侧行为依赖 Launch Services 缓存刷新，局部验证可能出现假阴性] -> Mitigation: 在任务和验证中加入重建运行产物与重新安装 app 后的检查步骤，必要时记录缓存刷新前提。
- [文档类型声明与现有打开链路脱节] -> Mitigation: 复用现有 `application(_:openFiles:)` 入口，不新增并行打开实现，并把该链路纳入验证范围。

## Migration Plan

1. 在 `MachOKnife/Info.plist` 中增加 Mach-O 相关文档类型与内容类型声明。
2. 构建并运行 app，检查生成的 bundle `Info.plist` 是否包含预期的 document types 和 UTI 声明。
3. 在 Finder 中验证支持文件的 `Open With` 候选和默认打开应用切换行为。
4. 验证系统从 Finder 打开文件时仍然进入现有工作区文档打开链路。
5. 如果 Launch Services 行为与预期不符，回滚只需移除新增文档类型声明；运行时代码不需要数据迁移。

## Open Questions

- 是否需要在实现阶段为某些系统已有 UTI 做额外兼容映射，才能覆盖更多第三方工具生成的 Mach-O / archive 文件？
- 是否要补充一份仓库内的手动验证文档，记录 Launch Services 缓存和 Finder 验证的注意事项？

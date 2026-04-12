import Foundation

enum L10n {
    static var settingsProvider: () -> AppSettings = { AppSettings.shared }
    static var bundleProvider: () -> Bundle = { .main }

    static var appName: String { text("app.name", fallback: "MachOKnife") }

    static var menuPreferences: String { text("menu.preferences", fallback: "Preferences...") }
    static var menuCheckForUpdates: String { text("menu.checkForUpdates", fallback: "Check for Updates...") }
    static var menuFile: String { text("menu.file", fallback: "File") }
    static var menuEdit: String { text("menu.edit", fallback: "Edit") }
    static var menuOpen: String { text("menu.open", fallback: "Open...") }
    static var menuCloseWindow: String { text("menu.closeWindow", fallback: "Close Window") }
    static var menuOpenRecent: String { text("menu.openRecent", fallback: "Open Recent") }
    static var menuOpenRecentEmpty: String { text("menu.openRecent.empty", fallback: "No Recent Files") }
    static var menuAnalyze: String { text("menu.analyze", fallback: "Analyze") }
    static var menuTools: String { text("menu.tools", fallback: "Tools") }
    static var menuRetag: String { text("menu.retag", fallback: "Retag...") }
    static var menuBuildXCFramework: String { text("menu.buildXCFramework", fallback: "Build XCFramework...") }
    static var menuMachOSummary: String { text("menu.machoSummary", fallback: "Mach-O Summary...") }
    static var menuCheckBinaryContamination: String { text("menu.checkBinaryContamination", fallback: "Check Binary Contamination...") }
    static var menuMergeSplitMachO: String { text("menu.mergeSplitMachO", fallback: "Merge / Split Mach-O...") }
    static var menuWindow: String { text("menu.window", fallback: "Window") }
    static var menuShowWorkspace: String { text("menu.showWorkspace", fallback: "Show Workspace") }
    static var menuHelp: String { text("menu.help", fallback: "Help") }
    static var menuGitHub: String { text("menu.github", fallback: "MachOKnife GitHub") }
    static var menuCopyNodeInfo: String { text("menu.copyNodeInfo", fallback: "Copy Node Info") }
    static var menuExportNodeInfo: String { text("menu.exportNodeInfo", fallback: "Export Node Info...") }
    static var menuShowCurrentFileInFinder: String { text("menu.showCurrentFileInFinder", fallback: "Show Current File in Finder") }
    static var menuCopyFilePath: String { text("menu.copyFilePath", fallback: "Copy File Path") }

    static func menuAbout(appName: String = appName) -> String {
        format("menu.about", fallback: "About %@", appName)
    }

    static func menuQuit(appName: String = appName) -> String {
        format("menu.quit", fallback: "Quit %@", appName)
    }

    static var workspaceWindowTitle: String { text("window.workspace.title", fallback: "MachOKnife") }
    static var openPanelTitle: String { text("window.openPanel.title", fallback: "Open Mach-O") }
    static var sourceListTitle: String { text("workspace.sourceList.title", fallback: "Structure") }
    static var sourceListSearchPlaceholder: String { text("workspace.sourceList.search", fallback: "Search Structure") }
    static var sourceListEmptyTitle: String { text("workspace.sourceList.empty.title", fallback: "No File Open") }
    static var sourceListEmptySubtitle: String { text("workspace.sourceList.empty.subtitle", fallback: "Open a Mach-O to browse its structure tree.") }
    static var sourceListNoResults: String { text("workspace.sourceList.empty.noResults", fallback: "No matching nodes") }
    static var viewerHeaderSection: String { text("workspace.viewer.header", fallback: "Header") }
    static var viewerLoadCommandsSection: String { text("workspace.viewer.loadCommands", fallback: "Load Commands") }
    static var viewerSegmentsSection: String { text("workspace.viewer.segments", fallback: "Segments") }
    static var viewerDylibsSection: String { text("workspace.viewer.dylibs", fallback: "Dynamic Libraries") }
    static var viewerRPathsSection: String { text("workspace.viewer.rpaths", fallback: "RPaths") }
    static var viewerSymbolsSection: String { text("workspace.viewer.symbols", fallback: "Symbols") }
    static var viewerDylibTitle: String { text("workspace.viewer.dylib.title", fallback: "Dynamic Library") }
    static var viewerRPathTitle: String { text("workspace.viewer.rpath.title", fallback: "RPath") }
    static var viewerSymbolTitle: String { text("workspace.viewer.symbol.title", fallback: "Symbol") }
    static var viewerFileLabel: String { text("workspace.viewer.file", fallback: "File") }
    static var viewerContainerLabel: String { text("workspace.viewer.container", fallback: "Container") }
    static var viewerSliceCountLabel: String { text("workspace.viewer.sliceCount", fallback: "Slice Count") }
    static var viewerCPUTypeLabel: String { text("workspace.viewer.cpuType", fallback: "CPU Type") }
    static var viewerCPUSubtypeLabel: String { text("workspace.viewer.cpuSubtype", fallback: "CPU Subtype") }
    static var viewerFileTypeLabel: String { text("workspace.viewer.fileType", fallback: "File Type") }
    static var viewerLoadCommandCountLabel: String { text("workspace.viewer.loadCommandCount", fallback: "Load Commands") }
    static var viewerSegmentCountLabel: String { text("workspace.viewer.segmentCount", fallback: "Segments") }
    static var viewerSymbolCountLabel: String { text("workspace.viewer.symbolCount", fallback: "Symbols") }
    static var viewerFileOffsetLabel: String { text("workspace.viewer.fileOffset", fallback: "File Offset") }
    static var viewerBitnessLabel: String { text("workspace.viewer.bitness", fallback: "64-bit") }
    static var viewerInstallNameLabel: String { text("workspace.viewer.installName", fallback: "Install Name") }
    static var viewerUUIDLabel: String { text("workspace.viewer.uuid", fallback: "UUID") }
    static var viewerPlatformLabel: String { text("workspace.viewer.platform", fallback: "Platform") }
    static var viewerMinimumOSLabel: String { text("workspace.viewer.minimumOS", fallback: "Minimum OS") }
    static var viewerSDKLabel: String { text("workspace.viewer.sdk", fallback: "SDK") }
    static var viewerCodeSignatureLabel: String { text("workspace.viewer.codeSignature", fallback: "Code Signature") }
    static var viewerEncryptionLabel: String { text("workspace.viewer.encryption", fallback: "Encryption") }
    static var viewerNumberOfCommandsLabel: String { text("workspace.viewer.numberOfCommands", fallback: "Number Of Commands") }
    static var viewerSizeOfCommandsLabel: String { text("workspace.viewer.sizeOfCommands", fallback: "Size Of Commands") }
    static var viewerFlagsLabel: String { text("workspace.viewer.flags", fallback: "Flags") }
    static var viewerReservedLabel: String { text("workspace.viewer.reserved", fallback: "Reserved") }
    static var viewerCountLabel: String { text("workspace.viewer.count", fallback: "Count") }
    static var viewerSizeLabel: String { text("workspace.viewer.size", fallback: "Size") }
    static var viewerOffsetLabel: String { text("workspace.viewer.offset", fallback: "Offset") }
    static var viewerVMAddressLabel: String { text("workspace.viewer.vmAddress", fallback: "VM Address") }
    static var viewerVMSizeLabel: String { text("workspace.viewer.vmSize", fallback: "VM Size") }
    static var viewerFileSizeLabel: String { text("workspace.viewer.fileSize", fallback: "File Size") }
    static var viewerMaxProtectionLabel: String { text("workspace.viewer.maxProtection", fallback: "Max Protection") }
    static var viewerInitialProtectionLabel: String { text("workspace.viewer.initialProtection", fallback: "Initial Protection") }
    static var viewerAddressLabel: String { text("workspace.viewer.address", fallback: "Address") }
    static var viewerAlignmentLabel: String { text("workspace.viewer.alignment", fallback: "Alignment") }
    static var viewerRelocationOffsetLabel: String { text("workspace.viewer.relocationOffset", fallback: "Relocation Offset") }
    static var viewerRelocationCountLabel: String { text("workspace.viewer.relocationCount", fallback: "Relocation Count") }
    static var viewerCommandLabel: String { text("workspace.viewer.command", fallback: "Command") }
    static var viewerPathLabel: String { text("workspace.viewer.path", fallback: "Path") }
    static var viewerValueLabel: String { text("workspace.viewer.value", fallback: "Value") }
    static var viewerNameLabel: String { text("workspace.viewer.name", fallback: "Name") }
    static var viewerTypeLabel: String { text("workspace.viewer.type", fallback: "Type") }
    static var viewerSectionLabel: String { text("workspace.viewer.section", fallback: "Section") }
    static var viewerDescriptionLabel: String { text("workspace.viewer.description", fallback: "Description") }
    static var viewerNoDecodedPayload: String { text("workspace.viewer.noDecodedPayload", fallback: "No decoded payload") }
    static var viewerNoSections: String { text("workspace.viewer.noSections", fallback: "No sections") }
    static var viewerDylibPathEditableHint: String { text("workspace.viewer.dylibPathEditableHint", fallback: "Path draft is editable in the inspector.") }
    static var viewerRPathEditableHint: String { text("workspace.viewer.rpathEditableHint", fallback: "RPath entries are editable in the inspector.") }
    static var viewerInstallNameDiffKind: String { text("workspace.viewer.diff.installName", fallback: "Install Name") }
    static var viewerDylibDiffKind: String { text("workspace.viewer.diff.dylib", fallback: "Dylib") }
    static var viewerRPathDiffKind: String { text("workspace.viewer.diff.rpath", fallback: "RPath") }
    static var viewerPlatformDiffKind: String { text("workspace.viewer.diff.platform", fallback: "Platform") }
    static var viewerSegmentProtectionDiffKind: String { text("workspace.viewer.diff.segmentProtection", fallback: "Segment Protection") }
    static var viewerCodeSignatureDiffKind: String { text("workspace.viewer.diff.codeSignature", fallback: "Code Signature") }
    static var viewerPresent: String { text("workspace.viewer.value.present", fallback: "present") }
    static var viewerMissing: String { text("workspace.viewer.value.missing", fallback: "missing") }
    static var viewerNone: String { text("workspace.viewer.value.none", fallback: "(none)") }
    static var viewerNA: String { text("workspace.viewer.value.na", fallback: "n/a") }
    static var viewerAnonymous: String { text("workspace.viewer.value.anonymous", fallback: "(anonymous)") }
    static var viewerRemoved: String { text("workspace.viewer.value.removed", fallback: "(removed)") }
    static var viewerYes: String { text("workspace.viewer.value.yes", fallback: "yes") }
    static var viewerNo: String { text("workspace.viewer.value.no", fallback: "no") }
    static var viewerBitness64: String { text("workspace.viewer.value.64bit", fallback: "64-bit") }
    static var viewerBitness32: String { text("workspace.viewer.value.32bit", fallback: "32-bit") }
    static var viewerCommandsShort: String { text("workspace.viewer.value.commandsShort", fallback: "cmds") }
    static var inspectorTitle: String { text("workspace.inspector.title", fallback: "Inspector") }
    static var inspectorPlaceholder: String { text("workspace.inspector.placeholder", fallback: "Dependencies and rpaths will appear here.") }
    static var inspectorTabOverview: String { text("workspace.inspector.tab.overview", fallback: "Overview") }
    static var inspectorTabDylibs: String { text("workspace.inspector.tab.dylibs", fallback: "Dylibs") }
    static var inspectorTabRPaths: String { text("workspace.inspector.tab.rpaths", fallback: "RPaths") }
    static var inspectorTabPlatform: String { text("workspace.inspector.tab.platform", fallback: "Platform") }
    static var inspectorTabPreview: String { text("workspace.inspector.tab.preview", fallback: "Preview") }
    static var inspectorInstallNameLabel: String { text("workspace.inspector.installName", fallback: "Install Name") }
    static var inspectorDylibsEmpty: String { text("workspace.inspector.dylibs.empty", fallback: "No load dylib commands in the selected slice.") }
    static var inspectorRPathsEmpty: String { text("workspace.inspector.rpaths.empty", fallback: "No rpaths in the selected slice.") }
    static var inspectorAddRPath: String { text("workspace.inspector.rpaths.add", fallback: "Add RPath") }
    static var inspectorRemoveAction: String { text("workspace.inspector.action.remove", fallback: "Remove") }
    static var inspectorPlatformLabel: String { text("workspace.inspector.platform.name", fallback: "Platform") }
    static var inspectorMinimumOSLabel: String { text("workspace.inspector.platform.min", fallback: "Minimum OS") }
    static var inspectorSDKLabel: String { text("workspace.inspector.platform.sdk", fallback: "SDK") }
    static var inspectorPlatformHint: String { text("workspace.inspector.platform.hint", fallback: "Use semantic versions like 17.4 or 17.4.0.") }
    static var inspectorPlatformUnavailable: String { text("workspace.inspector.platform.unavailable", fallback: "The selected slice has no editable platform metadata yet.") }
    static var inspectorPlatformInvalidVersion: String { text("workspace.inspector.platform.invalid", fallback: "Enter versions as major.minor or major.minor.patch.") }
    static var inspectorPreviewAction: String { text("workspace.inspector.preview.action", fallback: "Preview Changes") }
    static var inspectorPreviewPlaceholder: String { text("workspace.inspector.preview.placeholder", fallback: "Diff preview will appear here after you preview edits.") }
    static var workspaceEmptyTitle: String { text("workspace.empty.title", fallback: "Open a Mach-O to begin") }
    static var workspaceEmptySubtitle: String { text("workspace.empty.subtitle", fallback: "Drop a Mach-O, dylib, framework, or archive here, or choose Open to analyze it.") }
    static var workspaceEmptyOpenButton: String { text("workspace.empty.open", fallback: "Open File") }
    static var workspaceLoadingTitle: String { text("workspace.loading.title", fallback: "Loading Mach-O") }
    static var workspaceLoadingAnalyzing: String { text("workspace.loading.analyzing", fallback: "Scanning Mach-O metadata in the background.") }
    static var workspaceLoadingDeferredCollections: String { text("workspace.loading.deferred", fallback: "Large-file mode is active. Heavy collections are deferred until you expand them.") }
    static var workspaceAddressRaw: String { text("workspace.address.raw", fallback: "RAW") }
    static var workspaceAddressRVA: String { text("workspace.address.rva", fallback: "RVA") }
    static var workspaceDetailsTab: String { text("workspace.details.tab", fallback: "Detail") }
    static var workspaceHexTab: String { text("workspace.hex.tab", fallback: "Data") }
    static var workspaceDetailColumnAddress: String { text("workspace.detail.column.address", fallback: "Address") }
    static var workspaceDetailColumnData: String { text("workspace.detail.column.data", fallback: "Data") }
    static var workspaceDetailColumnName: String { text("workspace.detail.column.name", fallback: "Description") }
    static var workspaceDetailColumnValue: String { text("workspace.detail.column.value", fallback: "Value") }
    static var workspaceDetailEmpty: String { text("workspace.detail.empty", fallback: "Select a node in the tree to inspect its fields.") }
    static var workspaceDataEmpty: String { text("workspace.data.empty", fallback: "Binary data is unavailable for the current selection.") }
    static var workspaceContextCopyRow: String { text("workspace.context.copyRow", fallback: "Copy Row Info") }
    static var workspaceContextCopyAddress: String { text("workspace.context.copyAddress", fallback: "Copy Address") }
    static var workspaceContextCopyBinaryValue: String { text("workspace.context.copyBinaryValue", fallback: "Copy Binary Value") }
    static var workspaceContextCopyDescription: String { text("workspace.context.copyDescription", fallback: "Copy Description") }
    static var workspaceContextCopyValue: String { text("workspace.context.copyValue", fallback: "Copy Value") }
    static var workspaceContextCopyLowBytes: String { text("workspace.context.copyLowBytes", fallback: "Copy Data LO") }
    static var workspaceContextCopyHighBytes: String { text("workspace.context.copyHighBytes", fallback: "Copy Data HI") }
    static var workspaceHexPreviousPage: String { text("workspace.hex.previous", fallback: "Previous") }
    static var workspaceHexNextPage: String { text("workspace.hex.next", fallback: "Next") }
    static var workspaceHexUnavailable: String { text("workspace.hex.unavailable", fallback: "Hex data is unavailable for the current selection.") }
    static var menuCloseFile: String { text("menu.closeFile", fallback: "Close File") }
    static var nodeInfoExportTitle: String { text("nodeInfo.export.title", fallback: "Export Node Info") }
    static var nodeInfoExportDefaultName: String { text("nodeInfo.export.defaultName", fallback: "Node Info") }
    static var nodeInfoLargeCopyTitle: String { text("nodeInfo.copyLarge.title", fallback: "Large Text Copy") }
    static var nodeInfoLargeCopyExport: String { text("nodeInfo.copyLarge.export", fallback: "Export to File") }
    static var nodeInfoLargeCopyCopy: String { text("nodeInfo.copyLarge.copy", fallback: "Copy Anyway") }
    static var nodeInfoLargeCopyCancel: String { text("nodeInfo.copyLarge.cancel", fallback: "Cancel") }
    static var closeFileConfirmationTitle: String { text("closeFile.confirm.title", fallback: "Close Current File?") }
    static var closeFileConfirmationMessage: String { text("closeFile.confirm.message", fallback: "The current browser state will be cleared and the workspace will return to its initial state.") }
    static var closeFileConfirmationConfirm: String { text("closeFile.confirm.confirm", fallback: "Close File") }
    static var closeFileConfirmationCancel: String { text("closeFile.confirm.cancel", fallback: "Cancel") }

    static func nodeInfoLargeCopyMessage(_ lineCount: Int) -> String {
        format(
            "nodeInfo.copyLarge.message",
            fallback: "The selected node contains %d lines. Copying a large block of text may stall the app. Export it to a file instead?",
            lineCount
        )
    }

    static func viewerDeferredSymbolsMessage(_ count: Int) -> String {
        format(
            "workspace.viewer.symbols.deferred",
            fallback: "Showing the metadata shell. %d symbols are available through deferred browser pages.",
            count
        )
    }
    static var toolbarAnalyze: String { text("workspace.toolbar.analyze", fallback: "Analyze") }
    static var toolbarPreview: String { text("workspace.toolbar.preview", fallback: "Preview") }
    static var toolbarSave: String { text("workspace.toolbar.save", fallback: "Save") }

    static var preferencesWindowTitle: String { text("preferences.window.title", fallback: "Preferences") }
    static var preferencesGeneralTab: String { text("preferences.tab.general", fallback: "General") }
    static var preferencesCLITab: String { text("preferences.tab.cli", fallback: "CLI") }
    static var preferencesAppearanceTab: String { text("preferences.tab.appearance", fallback: "Appearance") }
    static var preferencesUpdatesTab: String { text("preferences.tab.updates", fallback: "Updates") }
    static var preferencesAdvancedTab: String { text("preferences.tab.advanced", fallback: "Advanced") }

    static var preferencesLanguageLabel: String { text("preferences.general.language", fallback: "App Language") }
    static var preferencesRecentFilesLabel: String { text("preferences.general.recentLimit", fallback: "Recent Files Limit") }
    static var preferencesRecentFilesHint: String { text("preferences.general.recentHint", fallback: "Controls how many recently opened files are retained.") }
    static var preferencesThemeLabel: String { text("preferences.appearance.theme", fallback: "Theme") }
    static var preferencesPlaceholderMilestone3: String { text("preferences.placeholder.milestone3", fallback: "Coming in Milestone 3.") }
    static var preferencesAdvancedTitle: String { text("preferences.advanced.title", fallback: "Advanced") }
    static var preferencesAdvancedSubtitle: String { text("preferences.advanced.subtitle", fallback: "Low-level tooling, CLI installation, and updater controls will appear here.") }
    static var preferencesUpdatesStatusLabel: String { text("preferences.updates.status", fallback: "Update Service") }
    static var preferencesUpdatesCheckStrategyLabel: String { text("preferences.updates.checkStrategy", fallback: "Check Frequency") }
    static var preferencesUpdatesAutomaticDownloadsLabel: String { text("preferences.updates.automaticDownloads", fallback: "Automatically download updates") }
    static var preferencesUpdatesAutomaticDownloadsHint: String { text("preferences.updates.automaticDownloads.hint", fallback: "Downloaded updates are staged and installed after you confirm the relaunch.") }
    static var preferencesUpdatesCheckNow: String { text("preferences.updates.checkNow", fallback: "Check Now") }
    static var preferencesUpdatesStatusReady: String { text("preferences.updates.status.ready", fallback: "Ready") }
    static var preferencesUpdatesStatusConfigurationRequired: String { text("preferences.updates.status.configurationRequired", fallback: "Configuration Required") }
    static var preferencesUpdatesDetailReady: String { text("preferences.updates.detail.ready", fallback: "Sparkle is configured and update checks are available.") }
    static var preferencesUpdatesDetailFeedURLMissing: String { text("preferences.updates.detail.feedURLMissing", fallback: "Set SUFeedURL in the app Info to enable Sparkle updates.") }
    static var preferencesUpdatesDetailPublicKeyMissing: String { text("preferences.updates.detail.publicKeyMissing", fallback: "Set SUPublicEDKey in the app Info to enable Sparkle updates.") }
    static var preferencesUpdatesDetailSparkleUnavailable: String { text("preferences.updates.detail.sparkleUnavailable", fallback: "Sparkle could not start in the current environment.") }
    static var preferencesCLIStatusLabel: String { text("preferences.cli.status", fallback: "Status") }
    static var preferencesCLIDirectoryLabel: String { text("preferences.cli.directory", fallback: "Install Directory") }
    static var preferencesCLIExecutableLabel: String { text("preferences.cli.executable", fallback: "Installed Executable") }
    static var preferencesCLIChooseDirectory: String { text("preferences.cli.choose", fallback: "Choose Directory…") }
    static var preferencesCLIInstall: String { text("preferences.cli.install", fallback: "Install CLI") }
    static var preferencesCLIUninstall: String { text("preferences.cli.uninstall", fallback: "Uninstall CLI") }
    static var preferencesCLIStatusNotConfigured: String { text("preferences.cli.status.notConfigured", fallback: "Not Configured") }
    static var preferencesCLIStatusReadyToInstall: String { text("preferences.cli.status.ready", fallback: "Ready to Install") }
    static var preferencesCLIStatusInstalled: String { text("preferences.cli.status.installed", fallback: "Installed") }
    static var preferencesCLIDirectoryNotConfigured: String { text("preferences.cli.directory.none", fallback: "No install directory selected.") }
    static var preferencesCLIExecutableNotInstalled: String { text("preferences.cli.executable.none", fallback: "CLI is not installed.") }
    static var preferencesCLIPathHelpGeneric: String { text("preferences.cli.pathHelp.generic", fallback: "Choose a writable directory and add it to PATH to run machoe-cli from Terminal.") }
    static var preferencesCLILastActionLabel: String { text("preferences.cli.lastAction", fallback: "Last Action") }
    static var preferencesCLILastActionIdle: String { text("preferences.cli.lastAction.idle", fallback: "No CLI action has run yet.") }
    static var preferencesCLIErrorTitle: String { text("preferences.cli.error.title", fallback: "CLI Installation") }
    static var retagWindowTitle: String { text("retag.window.title", fallback: "Retag Tool") }
    static var retagInputTitle: String { text("retag.input.title", fallback: "Input Mach-O") }
    static var retagInputChoose: String { text("retag.input.choose", fallback: "Choose File") }
    static var retagInputDropHint: String { text("retag.input.dropHint", fallback: "Drop a Mach-O, dylib, framework binary, or static archive here.") }
    static var retagInfoTitle: String { text("retag.info.title", fallback: "Detected Information") }
    static var retagArchitectureLabel: String { text("retag.architecture.label", fallback: "Architecture") }
    static var retagTargetLabel: String { text("retag.target.label", fallback: "Target Platform") }
    static var retagMinimumOSLabel: String { text("retag.minimumOS.label", fallback: "Minimum OS") }
    static var retagSDKLabel: String { text("retag.sdk.label", fallback: "SDK") }
    static var retagOutputDirectoryLabel: String { text("retag.output.directory", fallback: "Output Directory") }
    static var retagOutputNameLabel: String { text("retag.output.name", fallback: "File Name") }
    static var retagChooseDirectory: String { text("retag.output.choose", fallback: "Choose Directory…") }
    static var retagStart: String { text("retag.start", fallback: "Start Retag") }
    static var retagCancel: String { text("retag.cancel", fallback: "Cancel") }
    static var retagIdleStatus: String { text("retag.status.idle", fallback: "Select an input Mach-O to begin.") }
    static var retagRunningStatus: String { text("retag.status.running", fallback: "Retagging…") }
    static var retagCancelledStatus: String { text("retag.status.cancelled", fallback: "Retag cancelled.") }
    static var retagCompletedStatus: String { text("retag.status.completed", fallback: "Retag completed.") }
    static var retagUnsupportedPlaceholder: String { text("retag.placeholder.unsupported", fallback: "Retag currently supports rewriting platform metadata only. Additional SDK packaging flows will be added in a later pass.") }
    static var retagNoInputInfo: String { text("retag.info.empty", fallback: "No input selected.") }
    static var retagErrorTitle: String { text("retag.error.title", fallback: "Retag Failed") }
    static var retagOutputDefaultName: String { text("retag.output.defaultName", fallback: "Retagged") }
    static var xcframeworkWindowTitle: String { text("xcframework.window.title", fallback: "Build XCFramework") }
    static var xcframeworkSourceLibraryLabel: String { text("xcframework.sourceLibrary", fallback: "Source Library") }
    static var xcframeworkHelpTitle: String { text("xcframework.help.title", fallback: "Build Guidance") }
    static var xcframeworkHelpText: String {
        text(
            "xcframework.help.text",
            fallback: "Source Library is a fallback input. If iOS Device Library or iOS Simulator Library is empty, this file will be used instead. When both iOS Device and iOS Simulator libraries are already provided, Source Library can be left empty. If Mac Catalyst Library is empty, MachOKnife will retag supported arm64 and x86_64 slices from the iOS inputs and package them into the XCFramework automatically."
        )
    }
    static var xcframeworkDeviceLibraryLabel: String { text("xcframework.deviceLibrary", fallback: "iOS Device Library") }
    static var xcframeworkSimulatorLibraryLabel: String { text("xcframework.simulatorLibrary", fallback: "iOS Simulator Library") }
    static var xcframeworkMacCatalystLibraryLabel: String { text("xcframework.maccatalystLibrary", fallback: "Mac Catalyst Library") }
    static var xcframeworkMacCatalystOptionalHint: String { text("xcframework.maccatalyst.optionalHint", fallback: "Optional. Leave empty to build Mac Catalyst slices by retagging.") }
    static var xcframeworkHeadersLabel: String { text("xcframework.headers", fallback: "Headers Directory") }
    static var xcframeworkOutputDirectoryLabel: String { text("xcframework.outputDirectory", fallback: "Output Directory") }
    static var xcframeworkOutputLibraryNameLabel: String { text("xcframework.outputLibraryName", fallback: "Slice Library Name") }
    static var xcframeworkOutputNameLabel: String { text("xcframework.outputName", fallback: "XCFramework Name") }
    static var xcframeworkModuleNameLabel: String { text("xcframework.moduleName", fallback: "Module Name") }
    static var xcframeworkUmbrellaHeaderLabel: String { text("xcframework.umbrellaHeader", fallback: "Umbrella Header") }
    static var xcframeworkMinVersionLabel: String { text("xcframework.minVersion", fallback: "Mac Catalyst Min Version") }
    static var xcframeworkSDKVersionLabel: String { text("xcframework.sdkVersion", fallback: "Mac Catalyst SDK Version") }
    static var xcframeworkLogTitle: String { text("xcframework.log.title", fallback: "Build Log") }
    static var xcframeworkChooseFile: String { text("xcframework.chooseFile", fallback: "Choose File") }
    static var xcframeworkChooseDirectory: String { text("xcframework.chooseDirectory", fallback: "Choose Directory…") }
    static var xcframeworkStart: String { text("xcframework.start", fallback: "Build XCFramework") }
    static var xcframeworkCancel: String { text("xcframework.cancel", fallback: "Cancel") }
    static var summaryWindowTitle: String { text("summary.window.title", fallback: "Mach-O Summary") }
    static var summaryInputLabel: String { text("summary.input.label", fallback: "Input Binary") }
    static var summaryChooseInput: String { text("summary.input.choose", fallback: "Choose File") }
    static var summaryDropHint: String { text("summary.input.dropHint", fallback: "Drop a Mach-O, static archive, framework, or package here.") }
    static var summaryReportTitle: String { text("summary.report.title", fallback: "Summary Report") }
    static var summaryIdleStatus: String { text("summary.status.idle", fallback: "Select an input binary to inspect.") }
    static var summaryErrorTitle: String { text("summary.error.title", fallback: "Summary Failed") }
    static var contaminationWindowTitle: String { text("contamination.window.title", fallback: "Binary Contamination Check") }
    static var contaminationInputLabel: String { text("contamination.input.label", fallback: "Target Binary / Package") }
    static var contaminationModeLabel: String { text("contamination.mode.label", fallback: "Check Mode") }
    static var contaminationTargetLabel: String { text("contamination.target.label", fallback: "Expected Target") }
    static var contaminationAnalyze: String { text("contamination.analyze", fallback: "Start Check") }
    static var contaminationReportTitle: String { text("contamination.report.title", fallback: "Check Report") }
    static var contaminationIdleStatus: String { text("contamination.status.idle", fallback: "Select a target and start the check.") }
    static var contaminationModePlatform: String { text("contamination.mode.platform", fallback: "Platform") }
    static var contaminationModeArchitecture: String { text("contamination.mode.architecture", fallback: "Architecture") }
    static var contaminationErrorTitle: String { text("contamination.error.title", fallback: "Check Failed") }
    static var mergeSplitWindowTitle: String { text("mergeSplit.window.title", fallback: "Merge / Split Mach-O") }
    static var mergeSplitMergeTab: String { text("mergeSplit.tab.merge", fallback: "Merge") }
    static var mergeSplitSplitTab: String { text("mergeSplit.tab.split", fallback: "Split") }
    static var mergeSplitMergeInputsLabel: String { text("mergeSplit.merge.inputs", fallback: "Input Files") }
    static var mergeSplitMergeDropHint: String { text("mergeSplit.merge.dropHint", fallback: "Drop Mach-O files or static libraries here to append them to the merge list.") }
    static var mergeSplitMergeAddFiles: String { text("mergeSplit.merge.addFiles", fallback: "Add Files") }
    static var mergeSplitMergeRemove: String { text("mergeSplit.merge.remove", fallback: "Remove Selected") }
    static var mergeSplitMergeClear: String { text("mergeSplit.merge.clear", fallback: "Clear") }
    static var mergeSplitMergeOutputLabel: String { text("mergeSplit.merge.output", fallback: "Output File") }
    static var mergeSplitMergeChooseOutput: String { text("mergeSplit.merge.chooseOutput", fallback: "Choose Output…") }
    static var mergeSplitMergeStart: String { text("mergeSplit.merge.start", fallback: "Merge") }
    static var mergeSplitMergeIdleStatus: String { text("mergeSplit.merge.status.idle", fallback: "Add at least two input files to merge.") }
    static var mergeSplitSplitInputLabel: String { text("mergeSplit.split.input", fallback: "Input Fat Binary") }
    static var mergeSplitSplitChooseInput: String { text("mergeSplit.split.chooseInput", fallback: "Choose File") }
    static var mergeSplitSplitDropHint: String { text("mergeSplit.split.dropHint", fallback: "Drop a fat Mach-O or fat static archive here.") }
    static var mergeSplitSplitArchitecturesLabel: String { text("mergeSplit.split.architectures", fallback: "Detected Architectures") }
    static var mergeSplitSplitOutputDirectoryLabel: String { text("mergeSplit.split.outputDirectory", fallback: "Output Directory") }
    static var mergeSplitSplitChooseDirectory: String { text("mergeSplit.split.chooseDirectory", fallback: "Choose Directory…") }
    static var mergeSplitSplitStart: String { text("mergeSplit.split.start", fallback: "Split") }
    static var mergeSplitSplitIdleStatus: String { text("mergeSplit.split.status.idle", fallback: "Choose a fat binary to split.") }
    static var mergeSplitCompletedStatus: String { text("mergeSplit.status.completed", fallback: "Operation completed.") }
    static var mergeSplitErrorTitle: String { text("mergeSplit.error.title", fallback: "Merge / Split Failed") }
    static var xcframeworkIdleStatus: String { text("xcframework.status.idle", fallback: "Select headers and output directory, then provide Source Library or iOS Device Library to begin.") }
    static var xcframeworkRunningStatus: String { text("xcframework.status.running", fallback: "Building XCFramework…") }
    static var xcframeworkCancelledStatus: String { text("xcframework.status.cancelled", fallback: "XCFramework build cancelled.") }
    static var xcframeworkErrorTitle: String { text("xcframework.error.title", fallback: "XCFramework Build Failed") }
    static var xcframeworkNoSelection: String { text("xcframework.noSelection", fallback: "No selection.") }
    static var xcframeworkUseSourceLibraryHint: String { text("xcframework.useSourceLibrary", fallback: "Optional. Falls back to Source Library when empty.") }

    static func preferencesCLIPathHelp(directoryPath: String) -> String {
        format("preferences.cli.pathHelp.path", fallback: "Add %@ to PATH to run machoe-cli from Terminal.", directoryPath)
    }

    static func preferencesCLISuccessInstall(path: String) -> String {
        format("preferences.cli.success.install", fallback: "Installed machoe-cli to %@.", path)
    }

    static func preferencesCLISuccessUninstall(path: String) -> String {
        format("preferences.cli.success.uninstall", fallback: "Removed machoe-cli from %@.", path)
    }

    static func preferencesCLIInstallIncomplete(path: String) -> String {
        format("preferences.cli.install.incomplete", fallback: "machoe-cli was copied to %@, but the installed executable could not be validated yet.", path)
    }

    static func preferencesCLIErrorMessage(for error: Error) -> String {
        if let installError = error as? CLIInstallError {
            switch installError {
            case .installDirectoryNotConfigured:
                return text("preferences.cli.error.directoryMissing", fallback: "Choose an install directory before installing the CLI.")
            case .bundledCLINotFound:
                return text("preferences.cli.error.bundledMissing", fallback: "The bundled machoe-cli payload could not be found in the app.")
            }
        }

        return format("preferences.cli.error.generic", fallback: "The CLI operation failed: %@", error.localizedDescription)
    }

    static func retagCompletedStatus(path: String) -> String {
        format("retag.status.completedPath", fallback: "Retag completed: %@", path)
    }

    static func xcframeworkCompletedStatus(path: String) -> String {
        format("xcframework.status.completedPath", fallback: "XCFramework build completed: %@", path)
    }

    static func viewerSliceTitle(_ index: Int) -> String {
        format("workspace.viewer.slice.title", fallback: "Slice %ld", index)
    }

    static func viewerSliceOutlineTitle(index: Int, bitness: String, commandCount: Int) -> String {
        format("workspace.viewer.slice.outline", fallback: "Slice %1$ld • %2$@ • %3$ld cmds", index, bitness, commandCount)
    }

    static func viewerSegmentTitle(_ name: String) -> String {
        format("workspace.viewer.segment.title", fallback: "Segment %@", name)
    }

    static func viewerSectionTitle(_ qualifiedName: String) -> String {
        format("workspace.viewer.section.title", fallback: "Section %@", qualifiedName)
    }

    static func viewerDiffEntry(kind: String, originalValue: String, updatedValue: String) -> String {
        format("workspace.viewer.diff.entry", fallback: "%1$@: %2$@ -> %3$@", kind, originalValue, updatedValue)
    }

    static func languageName(_ language: AppLanguage) -> String {
        switch language {
        case .system:
            return text("language.system", fallback: "Follow System")
        case .english:
            return text("language.en", fallback: "English")
        case .simplifiedChinese:
            return text("language.zh-Hans", fallback: "Simplified Chinese")
        case .traditionalChinese:
            return text("language.zh-Hant", fallback: "Traditional Chinese")
        }
    }

    static func themeName(_ theme: AppTheme) -> String {
        switch theme {
        case .system:
            return text("theme.system", fallback: "Follow System")
        case .light:
            return text("theme.light", fallback: "Light")
        case .dark:
            return text("theme.dark", fallback: "Dark")
        }
    }

    static func updateCheckStrategyName(_ strategy: UpdateCheckStrategy) -> String {
        switch strategy {
        case .manual:
            return text("preferences.updates.checkStrategy.manual", fallback: "Manual Only")
        case .startup:
            return text("preferences.updates.checkStrategy.startup", fallback: "On Launch")
        case .daily:
            return text("preferences.updates.checkStrategy.daily", fallback: "Daily")
        }
    }

    private static func text(_ key: String, fallback: String) -> String {
        localization().string(key, fallback: fallback)
    }

    private static func format(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
        let formatString = text(key, fallback: fallback)
        return String(format: formatString, locale: Locale.current, arguments: arguments)
    }

    private static func localization() -> AppLocalization {
        let settings = settingsProvider()
        return AppLocalization(bundle: bundleProvider(), language: settings.resolvedLanguage())
    }
}

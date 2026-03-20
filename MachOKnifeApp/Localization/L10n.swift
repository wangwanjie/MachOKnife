import Foundation

enum L10n {
    static var settingsProvider: () -> AppSettings = { AppSettings.shared }
    static var bundleProvider: () -> Bundle = { .main }

    static var appName: String { text("app.name", fallback: "MachOKnife") }

    static var menuPreferences: String { text("menu.preferences", fallback: "Preferences...") }
    static var menuCheckForUpdates: String { text("menu.checkForUpdates", fallback: "Check for Updates...") }
    static var menuFile: String { text("menu.file", fallback: "File") }
    static var menuOpen: String { text("menu.open", fallback: "Open...") }
    static var menuOpenRecent: String { text("menu.openRecent", fallback: "Open Recent") }
    static var menuOpenRecentEmpty: String { text("menu.openRecent.empty", fallback: "No Recent Files") }
    static var menuAnalyze: String { text("menu.analyze", fallback: "Analyze") }
    static var menuWindow: String { text("menu.window", fallback: "Window") }
    static var menuShowWorkspace: String { text("menu.showWorkspace", fallback: "Show Workspace") }

    static func menuAbout(appName: String = appName) -> String {
        format("menu.about", fallback: "About %@", appName)
    }

    static func menuQuit(appName: String = appName) -> String {
        format("menu.quit", fallback: "Quit %@", appName)
    }

    static var workspaceWindowTitle: String { text("window.workspace.title", fallback: "MachOKnife") }
    static var openPanelTitle: String { text("window.openPanel.title", fallback: "Open Mach-O") }
    static var sourceListTitle: String { text("workspace.sourceList.title", fallback: "Structure") }
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
    static var preferencesCLIErrorTitle: String { text("preferences.cli.error.title", fallback: "CLI Installation") }

    static func preferencesCLIPathHelp(directoryPath: String) -> String {
        format("preferences.cli.pathHelp.path", fallback: "Add %@ to PATH to run machoe-cli from Terminal.", directoryPath)
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

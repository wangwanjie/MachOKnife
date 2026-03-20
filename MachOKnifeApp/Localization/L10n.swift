import Foundation

enum L10n {
    static var settingsProvider: () -> AppSettings = { AppSettings.shared }
    static var bundleProvider: () -> Bundle = { .main }

    static var appName: String { text("app.name", fallback: "MachOKnife") }

    static var menuPreferences: String { text("menu.preferences", fallback: "Preferences...") }
    static var menuFile: String { text("menu.file", fallback: "File") }
    static var menuOpen: String { text("menu.open", fallback: "Open...") }
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
    static var workspaceEmptyTitle: String { text("workspace.empty.title", fallback: "Open a Mach-O to begin") }
    static var workspaceEmptySubtitle: String { text("workspace.empty.subtitle", fallback: "Drop a Mach-O, dylib, framework, or archive here, or choose Open to analyze it.") }
    static var workspaceEmptyOpenButton: String { text("workspace.empty.open", fallback: "Open File") }

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

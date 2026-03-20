import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController {
    private static let autosaveName = NSWindow.FrameAutosaveName("MachOKnifePreferencesWindowFrame")

    convenience init() {
        self.init(settings: .shared, updateManager: UpdateManager())
    }

    init(settings: AppSettings, updateManager: UpdateManager) {
        let tabViewController = PreferencesTabViewController(settings: settings, updateManager: updateManager)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.preferencesWindowTitle
        window.center()
        window.contentViewController = tabViewController
        window.tabbingMode = .disallowed

        super.init(window: window)

        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(_ sender: Any?) {
        showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class PreferencesTabViewController: NSTabViewController {
    init(settings: AppSettings, updateManager: UpdateManager) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar

        addTab(title: L10n.preferencesGeneralTab, viewController: GeneralPreferencesViewController(settings: settings))
        addTab(title: L10n.preferencesCLITab, viewController: CLIPreferencesViewController(settings: settings))
        addTab(title: L10n.preferencesAppearanceTab, viewController: AppearancePreferencesViewController(settings: settings))
        addTab(title: L10n.preferencesUpdatesTab, viewController: UpdatesPreferencesViewController(updateManager: updateManager))
        addTab(title: L10n.preferencesAdvancedTab, viewController: AdvancedPreferencesViewController())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func addTab(title: String, viewController: NSViewController) {
        let item = NSTabViewItem(viewController: viewController)
        item.label = title
        addTabViewItem(item)
    }
}

@MainActor
private final class GeneralPreferencesViewController: NSViewController {
    private let settings: AppSettings
    private let languagePopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let recentFilesField = NSTextField(string: "")
    private let recentFilesStepper = NSStepper()

    init(settings: AppSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reloadControls()
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let languages = AppLanguage.allCases
        guard languages.indices.contains(sender.indexOfSelectedItem) else { return }
        settings.language = languages[sender.indexOfSelectedItem]
    }

    @objc private func recentFilesStepperChanged(_ sender: NSStepper) {
        settings.recentFilesLimit = sender.integerValue
        reloadControls()
    }

    @objc private func recentFilesFieldChanged(_ sender: NSTextField) {
        settings.recentFilesLimit = Int(sender.stringValue) ?? settings.recentFilesLimit
        reloadControls()
    }

    private func buildUI() {
        let languageLabel = makeSectionLabel(L10n.preferencesLanguageLabel)
        let recentFilesLabel = makeSectionLabel(L10n.preferencesRecentFilesLabel)
        let recentFilesHint = makeHintLabel(L10n.preferencesRecentFilesHint)

        languagePopUpButton.target = self
        languagePopUpButton.action = #selector(languageChanged(_:))
        languagePopUpButton.translatesAutoresizingMaskIntoConstraints = false
        languagePopUpButton.addItems(withTitles: AppLanguage.allCases.map(L10n.languageName(_:)))

        recentFilesField.alignment = .right
        recentFilesField.target = self
        recentFilesField.action = #selector(recentFilesFieldChanged(_:))
        recentFilesField.translatesAutoresizingMaskIntoConstraints = false

        recentFilesStepper.minValue = 1
        recentFilesStepper.maxValue = 500
        recentFilesStepper.increment = 1
        recentFilesStepper.target = self
        recentFilesStepper.action = #selector(recentFilesStepperChanged(_:))
        recentFilesStepper.translatesAutoresizingMaskIntoConstraints = false

        let recentFilesControls = NSStackView(views: [recentFilesField, recentFilesStepper])
        recentFilesControls.orientation = .horizontal
        recentFilesControls.alignment = .centerY
        recentFilesControls.spacing = 8
        recentFilesControls.translatesAutoresizingMaskIntoConstraints = false

        let languageRow = makeRow(label: languageLabel, control: languagePopUpButton)
        let recentFilesRow = makeRow(label: recentFilesLabel, control: recentFilesControls)

        let stack = NSStackView(views: [languageRow, recentFilesRow, recentFilesHint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            recentFilesField.widthAnchor.constraint(equalToConstant: 60),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func reloadControls() {
        if let index = AppLanguage.allCases.firstIndex(of: settings.language) {
            languagePopUpButton.selectItem(at: index)
        }

        recentFilesField.stringValue = "\(settings.recentFilesLimit)"
        recentFilesStepper.integerValue = settings.recentFilesLimit
    }
}

@MainActor
private final class AppearancePreferencesViewController: NSViewController {
    private let settings: AppSettings
    private let themePopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)

    init(settings: AppSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reloadControls()
    }

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        let themes = AppTheme.allCases
        guard themes.indices.contains(sender.indexOfSelectedItem) else { return }
        settings.theme = themes[sender.indexOfSelectedItem]
    }

    private func buildUI() {
        let themeLabel = makeSectionLabel(L10n.preferencesThemeLabel)

        themePopUpButton.target = self
        themePopUpButton.action = #selector(themeChanged(_:))
        themePopUpButton.translatesAutoresizingMaskIntoConstraints = false
        themePopUpButton.addItems(withTitles: AppTheme.allCases.map(L10n.themeName(_:)))

        let row = makeRow(label: themeLabel, control: themePopUpButton)
        view.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            row.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func reloadControls() {
        if let index = AppTheme.allCases.firstIndex(of: settings.theme) {
            themePopUpButton.selectItem(at: index)
        }
    }
}

@MainActor
private final class PlaceholderPreferencesViewController: NSViewController {
    private let message: String

    init(message: String) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = makePlaceholderView(title: nil, message: message)
    }
}

@MainActor
private final class AdvancedPreferencesViewController: NSViewController {
    override func loadView() {
        view = makePlaceholderView(
            title: L10n.preferencesAdvancedTitle,
            message: L10n.preferencesAdvancedSubtitle
        )
    }
}

@MainActor
func makeSectionLabel(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

@MainActor
func makeHintLabel(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = NSFont.systemFont(ofSize: 12)
    label.textColor = .secondaryLabelColor
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

@MainActor
func makeRow(label: NSTextField, control: NSView) -> NSStackView {
    let row = NSStackView(views: [label, control])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 16
    row.translatesAutoresizingMaskIntoConstraints = false
    return row
}

@MainActor
func makePlaceholderView(title: String?, message: String) -> NSView {
    let container = NSView()
    let views: [NSView]

    if let title {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        let messageLabel = makeHintLabel(message)
        views = [titleLabel, messageLabel]
    } else {
        views = [makeHintLabel(message)]
    }

    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)

    NSLayoutConstraint.activate([
        stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
        stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
        stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
    ])

    return container
}

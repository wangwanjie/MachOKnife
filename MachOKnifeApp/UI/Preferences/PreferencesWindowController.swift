import AppKit
import QuartzCore
import SnapKit

@MainActor
final class PreferencesWindowController: NSWindowController {
    private static let autosaveName = NSWindow.FrameAutosaveName("MachOKnifePreferencesWindowFrame")
    fileprivate static let minimumContentWidthFloor: CGFloat = 500
    fileprivate static let minimumContentHeight: CGFloat = 1
    private let preferencesViewController: PreferencesTabViewController
    private var settingsObserver: NSObjectProtocol?

    convenience init() {
        self.init(settings: .shared, updateManager: UpdateManager())
    }

    init(settings: AppSettings, updateManager: UpdateManager) {
        let tabViewController = PreferencesTabViewController(settings: settings, updateManager: updateManager)
        self.preferencesViewController = tabViewController
        let initialContentWidth = tabViewController.minimumContentWidth()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialContentWidth, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.preferencesWindowTitle
        window.center()
        window.contentViewController = tabViewController
        window.tabbingMode = .disallowed
        window.toolbarStyle = .preference
        let minimumFrameSize = window.frameRect(
            forContentRect: NSRect(x: 0, y: 0, width: initialContentWidth, height: Self.minimumContentHeight)
        ).size
        window.contentMinSize = NSSize(width: initialContentWidth, height: Self.minimumContentHeight)
        window.minSize = minimumFrameSize

        super.init(window: window)

        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        applyMinimumWidth(to: window, animated: false)
        window.setFrameAutosaveName(Self.autosaveName)
        observeSettings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    func present(_ sender: Any?) {
        showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func selectTab(at index: Int) {
        guard
            let tabViewController = window?.contentViewController as? NSTabViewController,
            tabViewController.tabViewItems.indices.contains(index)
        else {
            return
        }

        tabViewController.selectedTabViewItemIndex = index
    }

    func reloadLocalization() {
        window?.title = L10n.preferencesWindowTitle
        preferencesViewController.reloadLocalization()
        if let window {
            applyMinimumWidth(to: window, animated: true)
        }
        preferencesViewController.applyPreferredContentSize(animated: true)
    }

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadLocalization()
            }
        }
    }

    private func applyMinimumWidth(to window: NSWindow, animated: Bool) {
        let minimumContentWidth = preferencesViewController.minimumContentWidth()
        let minimumFrameSize = window.frameRect(
            forContentRect: NSRect(x: 0, y: 0, width: minimumContentWidth, height: Self.minimumContentHeight)
        ).size

        window.contentMinSize = NSSize(width: minimumContentWidth, height: Self.minimumContentHeight)
        window.minSize = minimumFrameSize

        guard window.frame.width < minimumFrameSize.width else {
            return
        }

        var frame = window.frame
        frame.origin.x += (frame.width - minimumFrameSize.width) / 2
        frame.size.width = minimumFrameSize.width

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: false)
        }
    }
}

@MainActor
private protocol PreferencesLocalizable: AnyObject {
    func reloadLocalization()
}

@MainActor
private final class PreferencesTabViewController: NSTabViewController, PreferencesLocalizable {
    private static let toolbarItemPadding: CGFloat = 38
    private static let toolbarIconAllowance: CGFloat = 18
    private static let toolbarInteritemSpacing: CGFloat = 12
    private static let toolbarOuterPadding: CGFloat = 36
    private let generalViewController: GeneralPreferencesViewController
    private let cliViewController: CLIPreferencesViewController
    private let appearanceViewController: AppearancePreferencesViewController
    private let updatesViewController: UpdatesPreferencesViewController
    private let advancedViewController: AdvancedPreferencesViewController

    init(settings: AppSettings, updateManager: UpdateManager) {
        self.generalViewController = GeneralPreferencesViewController(settings: settings)
        self.cliViewController = CLIPreferencesViewController(settings: settings)
        self.appearanceViewController = AppearancePreferencesViewController(settings: settings)
        self.updatesViewController = UpdatesPreferencesViewController(updateManager: updateManager)
        self.advancedViewController = AdvancedPreferencesViewController()
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar

        addTab(title: L10n.preferencesGeneralTab, symbolName: "slider.horizontal.3", viewController: generalViewController)
        addTab(title: L10n.preferencesCLITab, symbolName: "terminal", viewController: cliViewController)
        addTab(title: L10n.preferencesAppearanceTab, symbolName: "paintbrush", viewController: appearanceViewController)
        addTab(title: L10n.preferencesUpdatesTab, symbolName: "arrow.clockwise", viewController: updatesViewController)
        addTab(title: L10n.preferencesAdvancedTab, symbolName: "wrench.and.screwdriver", viewController: advancedViewController)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyPreferredContentSize(animated: false)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        applyPreferredContentSize(animated: true)
    }

    private func addTab(title: String, symbolName: String, viewController: NSViewController) {
        let wrappedViewController = PreferencesScrollContainerViewController(contentViewController: viewController)
        let item = NSTabViewItem(viewController: wrappedViewController)
        item.label = title
        item.image = tabSymbolImage(primary: symbolName, title: title)
        addTabViewItem(item)
    }

    func reloadLocalization() {
        if tabViewItems.indices.contains(0) {
            tabViewItems[0].label = L10n.preferencesGeneralTab
            tabViewItems[0].image = tabSymbolImage(primary: "slider.horizontal.3", fallback: "gearshape", title: L10n.preferencesGeneralTab)
        }
        if tabViewItems.indices.contains(1) {
            tabViewItems[1].label = L10n.preferencesCLITab
            tabViewItems[1].image = tabSymbolImage(primary: "terminal", fallback: "chevron.left.forwardslash.chevron.right", title: L10n.preferencesCLITab)
        }
        if tabViewItems.indices.contains(2) {
            tabViewItems[2].label = L10n.preferencesAppearanceTab
            tabViewItems[2].image = tabSymbolImage(primary: "paintbrush", fallback: "paintpalette", title: L10n.preferencesAppearanceTab)
        }
        if tabViewItems.indices.contains(3) {
            tabViewItems[3].label = L10n.preferencesUpdatesTab
            tabViewItems[3].image = tabSymbolImage(primary: "arrow.clockwise", fallback: "arrow.triangle.2.circlepath", title: L10n.preferencesUpdatesTab)
        }
        if tabViewItems.indices.contains(4) {
            tabViewItems[4].label = L10n.preferencesAdvancedTab
            tabViewItems[4].image = tabSymbolImage(primary: "wrench.and.screwdriver", fallback: "gearshape.2", title: L10n.preferencesAdvancedTab)
        }

        generalViewController.reloadLocalization()
        cliViewController.reloadLocalization()
        appearanceViewController.reloadLocalization()
        updatesViewController.reloadLocalization()
        advancedViewController.reloadLocalization()
    }

    func minimumContentWidth() -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let itemWidths = tabViewItems.map { item -> CGFloat in
            let labelWidth = (item.label as NSString).size(withAttributes: [.font: font]).width
            let iconWidth: CGFloat = item.image == nil ? 0 : Self.toolbarIconAllowance
            return ceil(labelWidth + iconWidth + Self.toolbarItemPadding)
        }
        let totalToolbarWidth = itemWidths.reduce(0, +)
            + CGFloat(max(0, tabViewItems.count - 1)) * Self.toolbarInteritemSpacing
            + Self.toolbarOuterPadding
        return max(PreferencesWindowController.minimumContentWidthFloor, totalToolbarWidth)
    }

    func applyPreferredContentSize(animated: Bool) {
        guard let window = view.window, let selected = selectedContentViewController else { return }

        selected.view.layoutSubtreeIfNeeded()

        let targetWidth = max(minimumContentWidth(), window.contentRect(forFrameRect: window.frame).width)
        selected.view.frame.size.width = targetWidth
        selected.view.layoutSubtreeIfNeeded()

        let fittedHeight = ceil(max(
            PreferencesWindowController.minimumContentHeight,
            selected.preferredContentSize.height > 0 ? selected.preferredContentSize.height : selected.view.fittingSize.height
        ))
        let visibleHeight = window.screen?.visibleFrame.height ?? 900
        let targetHeight = min(fittedHeight, visibleHeight - 120)
        let targetContentRect = NSRect(origin: .zero, size: NSSize(width: targetWidth, height: targetHeight))
        let targetFrame = window.frameRect(forContentRect: targetContentRect)
        var newFrame = window.frame
        newFrame.origin.y += newFrame.height - targetFrame.height
        newFrame.size = targetFrame.size

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: true)
        }
    }

    private var selectedContentViewController: NSViewController? {
        guard
            tabViewItems.indices.contains(selectedTabViewItemIndex),
            let wrapped = tabViewItems[selectedTabViewItemIndex].viewController as? PreferencesScrollContainerViewController
        else {
            return nil
        }

        return wrapped.contentViewController
    }

    private func tabSymbolImage(primary: String, fallback: String? = nil, title: String) -> NSImage? {
        if let image = NSImage(systemSymbolName: primary, accessibilityDescription: title) {
            return image
        }
        if let fallback, let image = NSImage(systemSymbolName: fallback, accessibilityDescription: title) {
            return image
        }
        return nil
    }
}

@MainActor
private final class PreferencesScrollContainerViewController: NSViewController {
    let contentViewController: NSViewController
    private let scrollView = NSScrollView()
    private let documentView = NSView()

    init(contentViewController: NSViewController) {
        self.contentViewController = contentViewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = NSView()
        let contentView = contentViewController.view

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        scrollView.documentView = documentView

        addChild(contentViewController)
        contentView.translatesAutoresizingMaskIntoConstraints = true
        contentView.autoresizingMask = [.width]
        let initialSize = initialContentSize(for: contentView)
        contentView.frame = NSRect(origin: .zero, size: initialSize)
        documentView.frame = NSRect(origin: .zero, size: initialSize)
        documentView.addSubview(contentView)

        rootView.addSubview(scrollView)
        view = rootView

        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        let contentWidth = max(PreferencesWindowController.minimumContentWidthFloor, scrollView.contentView.bounds.width)
        let fittingSize = contentViewController.view.fittingSize
        let contentSize = NSSize(width: contentWidth, height: fittingSize.height)

        contentViewController.view.frame = NSRect(origin: .zero, size: contentSize)
        documentView.frame = NSRect(origin: .zero, size: contentSize)
    }

    private func initialContentSize(for contentView: NSView) -> NSSize {
        let width = PreferencesWindowController.minimumContentWidthFloor
        contentView.frame.size.width = width
        contentView.layoutSubtreeIfNeeded()
        let height = max(1, contentView.fittingSize.height)
        return NSSize(width: width, height: height)
    }
}

@MainActor
private final class GeneralPreferencesViewController: NSViewController, PreferencesLocalizable {
    private static let preferredWidth: CGFloat = 640
    private static let verticalInset: CGFloat = 48
    private let settings: AppSettings
    private let languageLabel = makeSectionLabel("")
    private let recentFilesLabel = makeSectionLabel("")
    private let recentFilesHint = makeHintLabel("")
    private let languagePopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let recentFilesField = NSTextField(string: "")
    private let recentFilesStepper = NSStepper()
    private let contentStack = NSStackView()

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

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePreferredContentSize()
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
        languagePopUpButton.target = self
        languagePopUpButton.action = #selector(languageChanged(_:))

        recentFilesField.alignment = .right
        recentFilesField.target = self
        recentFilesField.action = #selector(recentFilesFieldChanged(_:))

        recentFilesStepper.minValue = 1
        recentFilesStepper.maxValue = 500
        recentFilesStepper.increment = 1
        recentFilesStepper.target = self
        recentFilesStepper.action = #selector(recentFilesStepperChanged(_:))

        let recentFilesControls = NSStackView(views: [recentFilesField, recentFilesStepper])
        recentFilesControls.orientation = .horizontal
        recentFilesControls.alignment = .centerY
        recentFilesControls.spacing = 8

        let languageRow = makeRow(label: languageLabel, control: languagePopUpButton)
        let recentFilesRow = makeRow(label: recentFilesLabel, control: recentFilesControls)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18
        [languageRow, recentFilesRow, recentFilesHint].forEach(contentStack.addArrangedSubview)

        view.addSubview(contentStack)

        recentFilesField.snp.makeConstraints { make in
            make.width.equalTo(60)
        }
        contentStack.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(24)
            make.trailing.lessThanOrEqualToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(24)
        }

        preferredContentSize = NSSize(width: Self.preferredWidth, height: 0)
        reloadLocalization()
    }

    private func reloadControls() {
        if let index = AppLanguage.allCases.firstIndex(of: settings.language) {
            languagePopUpButton.selectItem(at: index)
        }

        recentFilesField.stringValue = "\(settings.recentFilesLimit)"
        recentFilesStepper.integerValue = settings.recentFilesLimit
    }

    func reloadLocalization() {
        languageLabel.stringValue = L10n.preferencesLanguageLabel
        recentFilesLabel.stringValue = L10n.preferencesRecentFilesLabel
        recentFilesHint.stringValue = L10n.preferencesRecentFilesHint

        languagePopUpButton.removeAllItems()
        languagePopUpButton.addItems(withTitles: AppLanguage.allCases.map(L10n.languageName(_:)))
        reloadControls()
        updatePreferredContentSize()
    }

    private func updatePreferredContentSize() {
        view.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(
            width: Self.preferredWidth,
            height: ceil(contentStack.fittingSize.height + Self.verticalInset)
        )
    }
}

@MainActor
private final class AppearancePreferencesViewController: NSViewController, PreferencesLocalizable {
    private static let preferredWidth: CGFloat = 640
    private static let verticalInset: CGFloat = 48
    private let settings: AppSettings
    private let themeLabel = makeSectionLabel("")
    private let themePopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let contentStack = NSStackView()

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

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePreferredContentSize()
    }

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        let themes = AppTheme.allCases
        guard themes.indices.contains(sender.indexOfSelectedItem) else { return }
        settings.theme = themes[sender.indexOfSelectedItem]
    }

    private func buildUI() {
        themePopUpButton.target = self
        themePopUpButton.action = #selector(themeChanged(_:))

        let row = makeRow(label: themeLabel, control: themePopUpButton)
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.addArrangedSubview(row)
        view.addSubview(contentStack)

        contentStack.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(24)
            make.trailing.lessThanOrEqualToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(24)
        }

        preferredContentSize = NSSize(width: Self.preferredWidth, height: 0)
        reloadLocalization()
    }

    private func reloadControls() {
        if let index = AppTheme.allCases.firstIndex(of: settings.theme) {
            themePopUpButton.selectItem(at: index)
        }
    }

    func reloadLocalization() {
        themeLabel.stringValue = L10n.preferencesThemeLabel
        themePopUpButton.removeAllItems()
        themePopUpButton.addItems(withTitles: AppTheme.allCases.map(L10n.themeName(_:)))
        reloadControls()
        updatePreferredContentSize()
    }

    private func updatePreferredContentSize() {
        view.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(
            width: Self.preferredWidth,
            height: ceil(contentStack.fittingSize.height + Self.verticalInset)
        )
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
private final class AdvancedPreferencesViewController: NSViewController, PreferencesLocalizable {
    private static let preferredWidth: CGFloat = 640
    private static let verticalInset: CGFloat = 48
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = makeHintLabel("")
    private let contentStack = NSStackView()

    override func loadView() {
        let container = NSView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        [titleLabel, messageLabel].forEach(contentStack.addArrangedSubview)
        container.addSubview(contentStack)

        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)

        contentStack.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(24)
            make.trailing.lessThanOrEqualToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(24)
        }

        view = container
        preferredContentSize = NSSize(width: Self.preferredWidth, height: 0)
        reloadLocalization()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePreferredContentSize()
    }

    func reloadLocalization() {
        titleLabel.stringValue = L10n.preferencesAdvancedTitle
        messageLabel.stringValue = L10n.preferencesAdvancedSubtitle
        updatePreferredContentSize()
    }

    private func updatePreferredContentSize() {
        view.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(
            width: Self.preferredWidth,
            height: ceil(contentStack.fittingSize.height + Self.verticalInset)
        )
    }
}

@MainActor
func makeSectionLabel(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    return label
}

@MainActor
func makeHintLabel(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = NSFont.systemFont(ofSize: 12)
    label.textColor = .secondaryLabelColor
    return label
}

@MainActor
func makeCopyablePathLabel(_ text: String = "", wraps: Bool = false) -> NSTextField {
    let label = CopyableTextField(string: text, wraps: wraps)
    label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    label.textColor = .secondaryLabelColor
    if wraps {
        label.maximumNumberOfLines = 0
    } else {
        label.lineBreakMode = .byTruncatingMiddle
    }
    return label
}

@MainActor
func makeRow(label: NSTextField, control: NSView) -> NSStackView {
    let row = NSStackView(views: [label, control])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 16
    return row
}

@MainActor
final class CopyableTextField: NSTextField {
    init(string: String = "", wraps: Bool) {
        super.init(frame: .zero)
        stringValue = string
        isEditable = false
        isSelectable = true
        isBordered = false
        drawsBackground = false
        usesSingleLineMode = wraps == false
        lineBreakMode = wraps ? .byWordWrapping : .byTruncatingMiddle
        maximumNumberOfLines = wraps ? 0 : 1
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    @objc func copy(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedString() ?? stringValue, forType: .string)
    }

    override func selectAll(_ sender: Any?) {
        selectText(sender)
    }

    private func selectedString() -> String? {
        guard
            let editor = currentEditor(),
            editor.selectedRange.length > 0
        else {
            return nil
        }
        return (stringValue as NSString).substring(with: editor.selectedRange)
    }
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
    container.addSubview(stack)

    stack.snp.makeConstraints { make in
        make.top.leading.equalToSuperview().inset(24)
        make.trailing.lessThanOrEqualToSuperview().inset(24)
    }

    return container
}

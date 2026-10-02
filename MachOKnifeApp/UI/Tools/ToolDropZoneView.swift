import AppKit
import SnapKit

@MainActor
final class ToolDropZoneView: AdaptiveBackgroundView {
    let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let iconView = NSImageView()
    var onFileURLDropped: ((URL) -> Void)?
    var onFileURLsDropped: (([URL]) -> Void)?

    private var isDropTargetHighlighted = false {
        didSet {
            guard oldValue != isDropTargetHighlighted else { return }
            needsDisplay = true
        }
    }

    override init(backgroundColor: NSColor = .controlBackgroundColor) {
        super.init(backgroundColor: backgroundColor)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1.5
        layer?.masksToBounds = true

        iconView.image = NSImage(systemSymbolName: "square.and.arrow.down.on.square.dashed", accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        iconView.contentTintColor = .secondaryLabelColor

        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 0
        titleLabel.textColor = .secondaryLabelColor

        addSubview(iconView)
        addSubview(titleLabel)
        iconView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(titleLabel.snp.top).offset(-8)
        }
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(12)
            make.trailing.lessThanOrEqualToSuperview().offset(-12)
        }

        registerForDraggedTypes([.fileURL])
        needsDisplay = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Colors are applied in `updateLayer`, which AppKit calls with this view's effective
    // appearance set as the current drawing appearance, and again whenever it changes
    // (light/dark switch, accent color change), so the resolved `cgColor`s stay correct.
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let borderColor: NSColor
        let fillColor: NSColor
        if isDropTargetHighlighted {
            borderColor = .controlAccentColor
            fillColor = .controlAccentColor.withAlphaComponent(isDark ? 0.18 : 0.12)
        } else {
            borderColor = isDark ? .separatorColor : .controlAccentColor.withAlphaComponent(0.35)
            fillColor = isDark ? .controlBackgroundColor.withAlphaComponent(0.88) : .controlAccentColor.withAlphaComponent(0.08)
        }
        layer?.borderColor = borderColor.cgColor
        layer?.backgroundColor = fillColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard droppedURLs(from: sender).isEmpty == false else { return [] }
        isDropTargetHighlighted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTargetHighlighted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTargetHighlighted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTargetHighlighted = false
        let urls = droppedURLs(from: sender)
        guard urls.isEmpty == false else {
            return false
        }

        onFileURLsDropped?(urls)
        if let first = urls.first {
            onFileURLDropped?(first)
        }
        return true
    }

    private func droppedURLs(from sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
    }
}

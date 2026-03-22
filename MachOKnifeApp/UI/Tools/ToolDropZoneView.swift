import AppKit
import SnapKit

@MainActor
final class ToolDropZoneView: AdaptiveBackgroundView {
    let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let iconView = NSImageView()
    var onFileURLDropped: ((URL) -> Void)?
    var onFileURLsDropped: (([URL]) -> Void)?

    override init(backgroundColor: NSColor = .controlBackgroundColor) {
        super.init(backgroundColor: backgroundColor)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1.5
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9).cgColor

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
        updateBorderAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        updateBorderAppearance()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard
            let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
            items.isEmpty == false
        else {
            return false
        }

        updateBorderAppearance()
        onFileURLsDropped?(items)
        if let first = items.first {
            onFileURLDropped?(first)
        }
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorderAppearance()
    }

    private func updateBorderAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.borderColor = (isDark ? NSColor.separatorColor : NSColor.controlAccentColor.withAlphaComponent(0.35)).cgColor
        layer?.backgroundColor = (isDark
            ? NSColor.controlBackgroundColor.withAlphaComponent(0.88)
            : NSColor.controlAccentColor.withAlphaComponent(0.08)).cgColor
    }
}

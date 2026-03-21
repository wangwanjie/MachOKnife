import AppKit

class AdaptiveBackgroundView: NSView {
    private let backgroundColor: NSColor

    init(backgroundColor: NSColor) {
        self.backgroundColor = backgroundColor
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        dirtyRect.fill()
    }
}

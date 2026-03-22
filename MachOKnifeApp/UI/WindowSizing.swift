import AppKit

extension NSWindow {
    func restoreFrame(
        autosaveName: NSWindow.FrameAutosaveName,
        defaultSize: NSSize,
        minSize: NSSize
    ) {
        self.minSize = minSize

        let restored = setFrameUsingName(autosaveName)
        let currentFrame = frame
        let targetWidth = max(currentFrame.width, defaultSize.width)
        let targetHeight = max(currentFrame.height, defaultSize.height)
        let clampedSize = clampedWindowSize(
            proposedSize: NSSize(width: targetWidth, height: targetHeight),
            minSize: minSize
        )

        if restored {
            setFrame(
                NSRect(
                    x: currentFrame.origin.x,
                    y: currentFrame.origin.y,
                    width: clampedSize.width,
                    height: clampedSize.height
                ),
                display: false
            )
        } else {
            setContentSize(clampedWindowSize(proposedSize: defaultSize, minSize: minSize))
            center()
        }

        setFrameAutosaveName(autosaveName)
    }

    private func clampedWindowSize(proposedSize: NSSize, minSize: NSSize) -> NSSize {
        guard let screen = screen ?? NSScreen.main else {
            return NSSize(
                width: max(minSize.width, proposedSize.width),
                height: max(minSize.height, proposedSize.height)
            )
        }

        let visibleFrame = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        return NSSize(
            width: min(max(minSize.width, proposedSize.width), visibleFrame.width),
            height: min(max(minSize.height, proposedSize.height), visibleFrame.height)
        )
    }
}

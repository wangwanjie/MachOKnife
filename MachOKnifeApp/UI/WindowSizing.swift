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
        let width = max(currentFrame.width, defaultSize.width)
        let height = max(currentFrame.height, defaultSize.height)

        if restored {
            setFrame(
                NSRect(
                    x: currentFrame.origin.x,
                    y: currentFrame.origin.y,
                    width: width,
                    height: height
                ),
                display: false
            )
        } else {
            setContentSize(defaultSize)
            center()
        }

        setFrameAutosaveName(autosaveName)
    }
}

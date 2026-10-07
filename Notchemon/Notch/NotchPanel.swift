import AppKit

final class NotchPanel: NSPanel {
    var onEscape: (() -> Void)?

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // After isFloatingPanel, which would otherwise reset the level to .floating.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        animationBehavior = .none
    }

    // Borderless panels refuse key status by default; the quick-note field needs it.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // AppKit pushes windows below the menu bar; the notch lives inside it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    /// Hands keyboard focus back to whatever app the user was in, without
    /// activating anything ourselves.
    func relinquishKey() {
        guard isKeyWindow else { return }
        makeFirstResponder(nil)
        orderOut(nil)
        orderFrontRegardless()
    }
}

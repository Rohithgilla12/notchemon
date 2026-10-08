import AppKit

/// A titled, resizable panel with its title bar hidden under the content, so
/// it keeps rounded corners and resize edges but shows only our header.
final class NotesPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onCommand: ((NotesCommand) -> Bool)?

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isMovableByWindowBackground = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        minSize = NotesWindowFrame.minimumSize
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = NotesShortcut.command(
            characters: event.charactersIgnoringModifiers ?? "",
            keyCode: event.keyCode,
            command: flags.contains(.command),
            shift: flags.contains(.shift),
            option: flags.contains(.option),
            control: flags.contains(.control)
        )
        if let command, onCommand?(command) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

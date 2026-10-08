import AppKit
import SwiftUI

/// A stashed file's icon. Click opens it; dragging it out hands the file to
/// the drop target and, once the drop lands, removes it from the stash.
struct StashItemView: NSViewRepresentable {
    let url: URL
    let onRemove: (URL) -> Void

    func makeNSView(context: Context) -> StashItemNSView {
        StashItemNSView(url: url, onRemove: onRemove)
    }

    func updateNSView(_ view: StashItemNSView, context: Context) {
        view.url = url
        view.onRemove = onRemove
    }
}

final class StashItemNSView: NSView, NSDraggingSource {
    static let iconSide: CGFloat = 30
    static let badgeOverhang: CGFloat = 4
    static let side = iconSide + badgeOverhang

    var url: URL {
        didSet {
            needsDisplay = true
            toolTip = url.lastPathComponent
        }
    }
    var onRemove: (URL) -> Void
    private let badge = StashRemoveBadge()
    private var mouseDownEvent: NSEvent?

    init(url: URL, onRemove: @escaping (URL) -> Void) {
        self.url = url
        self.onRemove = onRemove
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        wantsLayer = true
        toolTip = url.lastPathComponent
        badge.onClick = { [weak self] in self?.remove() }
        addSubview(badge)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    private var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    override func layout() {
        super.layout()
        let side = StashRemoveBadge.side
        badge.frame = NSRect(x: bounds.maxX - side, y: bounds.maxY - side, width: side, height: side)
    }

    override func draw(_ dirtyRect: NSRect) {
        icon.draw(in: NSRect(x: 0, y: 0, width: Self.iconSide, height: Self.iconSide))
    }

    override func mouseEntered(with event: NSEvent) {
        badge.setShown(true)
    }

    // An icon that slides under a still cursor gets no mouse-entered, so the
    // first move inside it shows the badge instead.
    override func mouseMoved(with event: NSEvent) {
        if !badge.isShown { badge.setShown(true) }
    }

    override func mouseExited(with event: NSEvent) {
        badge.setShown(false)
    }

    // The panel is rarely key; without this the first press only focuses it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        mouseDownEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        if mouseDownEvent != nil { openFile() }
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent else { return }
        let distance = hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y)
        guard distance > 3 else { return }
        mouseDownEvent = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(NSRect(x: 0, y: 0, width: Self.iconSide, height: Self.iconSide), contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(menuItem("Open", #selector(openFile)))
        menu.addItem(menuItem("Reveal in Finder", #selector(revealInFinder)))
        menu.addItem(menuItem("Copy Path", #selector(copyPath)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Remove from Stash", #selector(remove)))
        return menu
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openFile() {
        NSWorkspace.shared.open(url)
    }

    @objc private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    @objc private func remove() {
        onRemove(url)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.move, .copy, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if !operation.isEmpty { onRemove(url) }
    }
}

final class StashRemoveBadge: NSView {
    static let side: CGFloat = 16
    var onClick: () -> Void = {}
    private(set) var isShown = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func setShown(_ shown: Bool) {
        isShown = shown
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = shown ? 1 : 0
        }
    }

    // A hidden badge must not take clicks: an item that slides under a still
    // cursor gets no mouse-entered until the cursor moves.
    override func hitTest(_ point: NSPoint) -> NSView? {
        isShown ? super.hitTest(point) : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        NSColor(white: 0.2, alpha: 1).setFill()
        circle.fill()
        NSColor(white: 1, alpha: 0.35).setStroke()
        circle.lineWidth = 1
        circle.stroke()
        let arm = bounds.insetBy(dx: 5, dy: 5)
        let glyph = NSBezierPath()
        glyph.move(to: NSPoint(x: arm.minX, y: arm.minY))
        glyph.line(to: NSPoint(x: arm.maxX, y: arm.maxY))
        glyph.move(to: NSPoint(x: arm.minX, y: arm.maxY))
        glyph.line(to: NSPoint(x: arm.maxX, y: arm.minY))
        glyph.lineWidth = 1.5
        glyph.lineCapStyle = .round
        NSColor.white.setStroke()
        glyph.stroke()
    }
}

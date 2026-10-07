import AppKit
import SwiftUI

/// A stashed file's icon. Click opens it; dragging it out hands the file to
/// the drop target and, once the drop lands, removes it from the stash.
struct StashItemView: NSViewRepresentable {
    let url: URL
    let onDraggedOut: (URL) -> Void

    func makeNSView(context: Context) -> StashItemNSView {
        StashItemNSView(url: url, onDraggedOut: onDraggedOut)
    }

    func updateNSView(_ view: StashItemNSView, context: Context) {
        view.url = url
        view.onDraggedOut = onDraggedOut
    }
}

final class StashItemNSView: NSView, NSDraggingSource {
    var url: URL { didSet { needsDisplay = true } }
    var onDraggedOut: (URL) -> Void
    private var mouseDownEvent: NSEvent?

    init(url: URL, onDraggedOut: @escaping (URL) -> Void) {
        self.url = url
        self.onDraggedOut = onDraggedOut
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    private var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    override func draw(_ dirtyRect: NSRect) {
        icon.draw(in: bounds)
    }

    // The panel is rarely key; without this the first press only focuses it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        if mouseDownEvent != nil { NSWorkspace.shared.open(url) }
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent else { return }
        let distance = hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y)
        guard distance > 3 else { return }
        mouseDownEvent = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: icon)
        _ = url.startAccessingSecurityScopedResource()
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.move, .copy, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        url.stopAccessingSecurityScopedResource()
        if !operation.isEmpty { onDraggedOut(url) }
    }
}

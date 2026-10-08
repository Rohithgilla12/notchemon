import AppKit

/// The dark translucent surface shared by the notes window and its slash menu.
enum NotesMaterial {
    static let windowCornerRadius: CGFloat = 16
    static let menuCornerRadius: CGFloat = 12
    static let highlight = NSColor.white.withAlphaComponent(0.1)

    /// Always `.active`: Notchemon is rarely the active app, and an inactive
    /// material renders as flat grey.
    static func makeView(cornerRadius: CGFloat) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        // A behind-window material is shaped by its mask image, not by its layer.
        view.maskImage = roundedMask(radius: cornerRadius)
        view.wantsLayer = true
        if let layer = view.layer {
            layer.cornerRadius = cornerRadius
            layer.cornerCurve = .continuous
            layer.masksToBounds = true
            layer.borderWidth = 0.5
            layer.borderColor = highlight.cgColor
        }
        return view
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

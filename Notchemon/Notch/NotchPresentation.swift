import CoreGraphics
import Observation

/// Window-side state the notch views render: where the notch is and whether
/// it is open. Creature state lives in `CompanionModel`.
@MainActor
@Observable
final class NotchPresentation {
    var layout: NotchLayout?
    var mode: PanelMode = .collapsed
    /// The notch opens on a click instead of on hover.
    var clickToOpen = false
    var isFullScreen = false
    var isDropTargeted = false
    var shakeToken = 0
    /// Set by the hotkey; the note field takes focus and clears it.
    var noteFocusRequested = false
    /// A click on the notch or on empty panel space, with `clickToOpen` on.
    @ObservationIgnored var onClick: (() -> Void)?

    var isExpanded: Bool { mode.isExpanded }

    var metrics: PanelMetrics? {
        layout.map(PanelMetrics.init(layout:))
    }
}

/// Local, top-left-origin geometry of the panel content, which fills the
/// expanded rect. The window is that rect widened to the strip the creature
/// wanders along, so collapse and expand animate inside a window that never
/// resizes.
struct PanelMetrics: Sendable, Equatable {
    let windowSize: CGSize
    let panelSize: CGSize
    let notchSize: CGSize
    let peekHeight: CGFloat

    init(layout: NotchLayout) {
        windowSize = layout.panel.size
        panelSize = layout.expanded.size
        notchSize = layout.notch.size
        peekHeight = layout.collapsed.height - layout.notch.height
    }

    /// Wide enough for a creature turned sideways at about twice its
    /// collapsed size, and tall enough for the panel's anims standing on one
    /// ground line, a wake curled below it included. The slot fills the
    /// panel's left column.
    static let expandedSpriteSize = CGSize(width: 136, height: 120)
    static let expandedInset: CGFloat = 16
    static let expandedVerticalPadding: CGFloat = 12

    var collapsedSpriteSide: CGFloat { peekHeight }

    /// The peek strip below the notch. Taller frames rise behind the notch.
    var collapsedSpriteFrame: CGRect {
        let side = collapsedSpriteSide
        return CGRect(x: (panelSize.width - side) / 2, y: notchSize.height + peekHeight - side, width: side, height: side)
    }

    var expandedSpriteFrame: CGRect {
        CGRect(origin: CGPoint(x: Self.expandedInset, y: notchSize.height + Self.expandedVerticalPadding), size: Self.expandedSpriteSize)
    }

    func spriteFrame(expanded: Bool) -> CGRect {
        expanded ? expandedSpriteFrame : collapsedSpriteFrame
    }

    /// The creature's centre in global screen coordinates, `roamX` points
    /// from home along the strip when the panel is closed.
    func spriteCentre(expanded: Bool, roamX: Double, panelFrame: CGRect) -> CGPoint {
        let frame = spriteFrame(expanded: expanded)
        let centre = screenPoint(CGPoint(x: frame.midX, y: frame.midY), panelFrame: panelFrame)
        return expanded ? centre : CGPoint(x: centre.x + roamX, y: centre.y)
    }

    /// Converts a local sprite centre to global screen coordinates.
    func screenPoint(_ local: CGPoint, panelFrame: CGRect) -> CGPoint {
        CGPoint(x: panelFrame.minX + local.x, y: panelFrame.maxY - local.y)
    }
}

import CoreGraphics
import Observation

/// Window-side state the notch views render: where the notch is and whether
/// it is open. Creature state lives in `CompanionModel`.
@MainActor
@Observable
final class NotchPresentation {
    var layout: NotchLayout?
    var mode: PanelMode = .collapsed
    var isFullScreen = false
    var isDropTargeted = false
    var shakeToken = 0
    /// Set by the hotkey; the note field takes focus and clears it.
    var noteFocusRequested = false

    var isExpanded: Bool { mode.isExpanded }

    var metrics: PanelMetrics? {
        layout.map(PanelMetrics.init(layout:))
    }
}

/// Local, top-left-origin geometry of the panel content. The panel window is
/// always the expanded rect, so collapse and expand animate inside a window
/// that never resizes.
struct PanelMetrics: Sendable, Equatable {
    let panelSize: CGSize
    let notchSize: CGSize
    let peekHeight: CGFloat

    init(layout: NotchLayout) {
        panelSize = layout.expanded.size
        notchSize = layout.notch.size
        peekHeight = layout.collapsed.height - layout.notch.height
    }

    static let expandedSpriteSide: CGFloat = 100
    static let expandedInset: CGFloat = 16
    static let expandedVerticalPadding: CGFloat = 12

    var collapsedSpriteSide: CGFloat { peekHeight }

    /// The peek strip below the notch. Taller frames rise behind the notch.
    var collapsedSpriteFrame: CGRect {
        let side = collapsedSpriteSide
        return CGRect(x: (panelSize.width - side) / 2, y: notchSize.height + peekHeight - side, width: side, height: side)
    }

    var expandedSpriteFrame: CGRect {
        let side = Self.expandedSpriteSide
        return CGRect(x: Self.expandedInset + 8, y: notchSize.height + Self.expandedVerticalPadding, width: side, height: side)
    }

    func spriteFrame(expanded: Bool) -> CGRect {
        expanded ? expandedSpriteFrame : collapsedSpriteFrame
    }

    /// Converts a local sprite centre to global screen coordinates.
    func screenPoint(_ local: CGPoint, panelFrame: CGRect) -> CGPoint {
        CGPoint(x: panelFrame.minX + local.x, y: panelFrame.maxY - local.y)
    }
}

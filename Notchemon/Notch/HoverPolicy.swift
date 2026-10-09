import CoreGraphics

enum ExpandReason: Sendable, Equatable {
    case hover
    /// Opened by the hotkey or onboarding; stays open until the cursor visits
    /// and leaves, or the hotkey closes it.
    case pinned
    /// Opened by a click with Click to Open on; stays open wherever the
    /// cursor goes until a click on the notch or empty panel space.
    case clicked
}

enum PanelMode: Sendable, Equatable {
    case collapsed
    case expanded(ExpandReason)

    var isExpanded: Bool { self != .collapsed }
}

/// What the pending collapse timer should do.
enum CollapseAction: Sendable, Equatable {
    case schedule
    case cancel
    case unchanged
}

struct HoverDecision: Sendable, Equatable {
    var mode: PanelMode
    /// Whether the panel should receive mouse events. Outside the notch it must
    /// not, so menu-bar icons beside the notch stay clickable.
    var hitTestable: Bool
    var collapse: CollapseAction
}

enum HoverPolicy {
    /// `buttonHeld` is a press in another app that is not dragging files: the
    /// panel neither opens nor closes under it, but takes clicks only while
    /// it is open under the cursor. With `clickToOpen`, the cursor never opens
    /// the panel; it only makes the notch clickable. `wild` is a visiting
    /// creature's box, which takes a click to catch it and opens nothing.
    static func react(
        to cursor: CGPoint, mode: PanelMode, layout: NotchLayout, buttonHeld: Bool = false, clickToOpen: Bool = false, wild: CGRect? = nil
    ) -> HoverDecision {
        var decision = panel(to: cursor, mode: mode, layout: layout, buttonHeld: buttonHeld, clickToOpen: clickToOpen)
        if !buttonHeld, let wild, wild.contains(cursor) { decision.hitTestable = true }
        return decision
    }

    /// A visiting creature's box around its centre: the box the sprite is drawn in.
    static func wildBox(centre: CGPoint, side: CGFloat = NotchGeometry.peekHeight) -> CGRect {
        CGRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
    }

    private static func panel(to cursor: CGPoint, mode: PanelMode, layout: NotchLayout, buttonHeld: Bool, clickToOpen: Bool) -> HoverDecision {
        if buttonHeld {
            let hitTestable = mode.isExpanded && layout.expanded.contains(cursor)
            return HoverDecision(mode: mode, hitTestable: hitTestable, collapse: .unchanged)
        }
        switch mode {
        case .collapsed:
            let inside = layout.collapsed.contains(cursor)
            let expand = inside && !clickToOpen
            return HoverDecision(mode: expand ? .expanded(.hover) : .collapsed, hitTestable: inside, collapse: .cancel)
        case .expanded(.hover):
            let inside = layout.expanded.contains(cursor)
            return HoverDecision(mode: mode, hitTestable: inside, collapse: inside ? .cancel : .schedule)
        case .expanded(.clicked) where clickToOpen:
            return HoverDecision(mode: mode, hitTestable: layout.expanded.contains(cursor), collapse: .cancel)
        case .expanded(.pinned), .expanded(.clicked):
            let inside = layout.expanded.contains(cursor)
            return HoverDecision(mode: inside ? .expanded(.hover) : mode, hitTestable: inside, collapse: .cancel)
        }
    }

    /// A click on the notch or on empty panel space, which the panel receives
    /// only with Click to Open on. Controls inside the panel take their own
    /// clicks and never get here.
    static func click(mode: PanelMode) -> PanelMode {
        mode.isExpanded ? .collapsed : .expanded(.clicked)
    }
}

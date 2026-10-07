import CoreGraphics

enum ExpandReason: Sendable, Equatable {
    case hover
    /// Opened by the hotkey or onboarding; stays open until the cursor visits
    /// and leaves, or the hotkey closes it.
    case pinned
}

enum PanelMode: Sendable, Equatable {
    case collapsed
    case expanded(ExpandReason)

    var isExpanded: Bool { self != .collapsed }
}

struct HoverDecision: Sendable, Equatable {
    var mode: PanelMode
    /// Whether the panel should receive mouse events. Outside the notch it must
    /// not, so menu-bar icons beside the notch stay clickable.
    var hitTestable: Bool
    var scheduleCollapse: Bool
    var hop: Bool
}

enum HoverPolicy {
    static func react(to cursor: CGPoint, mode: PanelMode, layout: NotchLayout) -> HoverDecision {
        switch mode {
        case .collapsed:
            let inside = layout.collapsed.contains(cursor)
            return HoverDecision(mode: inside ? .expanded(.hover) : .collapsed, hitTestable: inside, scheduleCollapse: false, hop: inside)
        case .expanded(.hover):
            let inside = layout.expanded.contains(cursor)
            return HoverDecision(mode: mode, hitTestable: inside, scheduleCollapse: !inside, hop: false)
        case .expanded(.pinned):
            let inside = layout.expanded.contains(cursor)
            return HoverDecision(mode: inside ? .expanded(.hover) : mode, hitTestable: inside, scheduleCollapse: false, hop: false)
        }
    }
}

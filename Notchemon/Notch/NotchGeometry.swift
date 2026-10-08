import CoreGraphics

/// The subset of `NSScreen` that notch layout depends on, so layout is testable
/// without a display.
struct ScreenMetrics: Sendable, Equatable {
    var frame: CGRect
    var safeAreaTop: CGFloat
    var auxiliaryTopLeftWidth: CGFloat
    var auxiliaryTopRightWidth: CGFloat
}

enum NotchKind: Sendable, Equatable { case hardware, virtual }

struct NotchLayout: Sendable, Equatable {
    let kind: NotchKind
    /// The notch cut-out in global screen coordinates (origin bottom-left).
    let notch: CGRect
    /// Notch plus the strip below it where the sprite peeks out. The only
    /// part of the closed panel that takes the mouse.
    let collapsed: CGRect
    let expanded: CGRect
    /// How far either side of home the creature's centre may wander, in points.
    let roamReach: CGFloat
    /// The window: the expanded panel and the strip below the menu bar the
    /// creature wanders along, which it never leaves.
    let panel: CGRect
}

enum NotchGeometry {
    static let virtualSize = CGSize(width: 180, height: 32)
    /// Room for a creature about 40 pt tall below the notch.
    static let peekHeight: CGFloat = 44
    static let fullScreenPeekHeight: CGFloat = 20
    static let expandedSize = CGSize(width: 440, height: 180)
    static let nearNotchReach: CGFloat = 200
    /// How far the creature's centre stays from the screen's side edges:
    /// room for the widest creature at its collapsed scale, turned sideways.
    static let roamEdgeInset: CGFloat = 60

    /// How far either side of the notch centre the creature may walk on a
    /// screen this wide. The notch is centred on its screen, so one reach
    /// keeps both sides on it.
    static func roamReach(_ wander: WanderRange, screenWidth: CGFloat) -> CGFloat {
        let edge = max(0, screenWidth / 2 - roamEdgeInset)
        return switch wander {
        case .off, .dock: 0
        case .nearNotch: min(nearNotchReach, edge)
        case .topEdge, .topEdgeAndDock: edge
        }
    }

    /// Returns nil when the screen has no notch and the virtual notch is off.
    /// Full screen keeps the creature home, so the strip shrinks to the notch.
    /// `covering` is how far from home the creature stands or walks: past a
    /// range that just narrowed, the strip stays wide enough to show it
    /// walking back in.
    static func layout(for screen: ScreenMetrics, virtualNotchEnabled: Bool, fullScreen: Bool = false, wander: WanderRange, covering: CGFloat = 0) -> NotchLayout? {
        let kind: NotchKind
        let size: CGSize
        if screen.safeAreaTop > 0 {
            kind = .hardware
            let width = screen.frame.width - screen.auxiliaryTopLeftWidth - screen.auxiliaryTopRightWidth
            size = CGSize(width: width, height: screen.safeAreaTop)
        } else if virtualNotchEnabled {
            kind = .virtual
            size = virtualSize
        } else {
            return nil
        }

        let notch = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        let peek = fullScreen ? fullScreenPeekHeight : peekHeight
        let collapsed = CGRect(x: notch.minX, y: notch.minY - peek, width: notch.width, height: notch.height + peek)
        let expandedWidth = max(expandedSize.width, notch.width)
        let expandedHeight = expandedSize.height + notch.height
        let expanded = CGRect(
            x: screen.frame.midX - expandedWidth / 2,
            y: screen.frame.maxY - expandedHeight,
            width: expandedWidth,
            height: expandedHeight
        )
        let reach = fullScreen ? 0 : roamReach(wander, screenWidth: screen.frame.width)
        let halfStrip = max(reach, covering) + roamEdgeInset
        let strip = CGRect(x: notch.midX - halfStrip, y: collapsed.minY, width: 2 * halfStrip, height: collapsed.height)
        let panel = expanded.union(strip.intersection(screen.frame))
        return NotchLayout(kind: kind, notch: notch, collapsed: collapsed, expanded: expanded, roamReach: reach, panel: panel)
    }
}

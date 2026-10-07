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
    /// Notch plus the strip below it where the sprite peeks out.
    let collapsed: CGRect
    let expanded: CGRect
}

enum NotchGeometry {
    static let virtualSize = CGSize(width: 180, height: 32)
    /// Room for a creature about 40 pt tall below the notch.
    static let peekHeight: CGFloat = 44
    static let fullScreenPeekHeight: CGFloat = 20
    static let expandedSize = CGSize(width: 420, height: 160)

    /// Returns nil when the screen has no notch and the virtual notch is off.
    static func layout(for screen: ScreenMetrics, virtualNotchEnabled: Bool, fullScreen: Bool = false) -> NotchLayout? {
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
        return NotchLayout(kind: kind, notch: notch, collapsed: collapsed, expanded: expanded)
    }
}

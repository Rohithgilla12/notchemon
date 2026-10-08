import CoreGraphics

enum DockOrientation: String, Sendable, Equatable {
    case bottom, left, right
}

/// What the Dock reports about itself at one instant.
struct DockReading: Sendable, Equatable {
    /// The Dock's icon list in AppKit global coordinates (origin at the
    /// bottom-left of the primary display), or nil when it could not be read.
    var listFrame: CGRect?
    var orientation: DockOrientation
    var autoHides: Bool
}

/// A rise in the ground the creature walks on: `height` points up over
/// `span`, flat elsewhere. x is measured as along the perch.
struct GroundStep: Sendable, Equatable {
    var span: ClosedRange<Double>
    var height: Double

    func height(at x: Double) -> Double {
        span.contains(x) ? height : 0
    }
}

/// An auto-hiding Dock, which the creature walks under along the screen's
/// bottom edge and climbs onto while it is shown.
struct AutoHidingDock: Sendable, Equatable {
    enum Slide: Sendable, Equatable {
        /// Wholly below the screen.
        case hidden
        /// Part way in or out. It takes about a quarter of a second either way.
        case sliding
        /// Wholly on the screen.
        case shown
    }

    /// The icon list's left and right edges in global x.
    let span: ClosedRange<CGFloat>
    /// The list's top edge in global y once it has slid fully into view.
    let top: CGFloat
    let slide: Slide

    var revealed: Bool { slide == .shown }
}

/// Where the creature walks along the bottom of a screen with a bottom Dock.
struct DockShelf: Sendable, Equatable {
    /// The frame of the screen the Dock is on.
    let screen: CGRect
    /// Where the creature's feet go unless a shown auto-hiding Dock lifts
    /// them: the top of a Dock that stays shown, or the screen's bottom edge.
    let ground: CGFloat
    /// Where the creature's centre may stand, in global x.
    let walkable: ClosedRange<CGFloat>
    /// Nil for a Dock that stays shown.
    var autoHide: AutoHidingDock?

    /// Positions on the Dock are measured from here, rightwards positive.
    var centreX: CGFloat { (walkable.lowerBound + walkable.upperBound) / 2 }

    /// Where the creature's centre may stand, in points from `centreX`.
    var range: ClosedRange<Double> {
        let half = Double(walkable.upperBound - walkable.lowerBound) / 2
        return -half...half
    }

    /// The creature's box stands on the Dock with the same side as the peek
    /// below the notch, so it is drawn at the same scale.
    static let spriteSide = NotchGeometry.peekHeight

    /// The shown auto-hiding Dock, in x from `centreX`, or nil while nothing raises the ground.
    var step: GroundStep? {
        guard let autoHide, autoHide.revealed else { return nil }
        let span = Double(autoHide.span.lowerBound - centreX)...Double(autoHide.span.upperBound - centreX)
        return GroundStep(span: span, height: Double(autoHide.top - ground))
    }

    /// The window the creature walks in: as wide as the walk, its bottom on
    /// the ground, and tall enough above a shown Dock's top for a hop. It
    /// does not change as an auto-hiding Dock slides, so the walk inside it
    /// carries on undisturbed.
    var panel: CGRect {
        let climb = autoHide.map { $0.top - ground } ?? 0
        return CGRect(
            x: walkable.lowerBound - DockGeometry.edgeInset,
            y: ground,
            width: walkable.upperBound - walkable.lowerBound + 2 * DockGeometry.edgeInset,
            height: climb + 2 * Self.spriteSide
        )
    }

    /// The creature's centre in global screen coordinates, `x` points along the Dock.
    func spriteCentre(x: Double) -> CGPoint {
        CGPoint(x: centreX + x, y: ground + (step?.height(at: x) ?? 0) + Self.spriteSide / 2)
    }

    /// Whether a cursor at `point` should have an auto-hiding Dock shown,
    /// or nil for a Dock that stays shown. It slides up once the cursor
    /// reaches the screen's bottom edge and back down once it leaves the Dock.
    func cursorShowsDock(_ point: CGPoint) -> Bool? {
        guard let autoHide else { return nil }
        guard (screen.minX..<screen.maxX).contains(point.x), point.y >= screen.minY else { return false }
        if point.y <= screen.minY + DockGeometry.revealEdge { return true }
        return autoHide.slide != .hidden && autoHide.span.contains(point.x) && point.y <= autoHide.top
    }
}

enum DockGeometry {
    /// Half the creature's collapsed width, so it never hangs off the Dock's ends.
    static let edgeInset: CGFloat = NotchGeometry.peekHeight / 2
    /// Under an auto-hiding Dock the creature keeps this much further from the screen's sides.
    static let screenMargin: CGFloat = 8
    /// A Dock with less room than this to walk is not worth stepping onto.
    static let minimumWalk: CGFloat = 80
    /// How far above the screen's bottom a shown auto-hiding Dock's list
    /// sits. Hidden, it reports only its size, so its shown top is taken
    /// from this, as measured on macOS 27.
    static let shownLift: CGFloat = 10
    /// How close to the screen's bottom the cursor comes before an auto-hiding Dock slides up.
    static let revealEdge: CGFloat = 3

    /// Nil unless the Dock sits at the bottom of one of `screens` with room
    /// to walk and no full-screen app covers that screen. A Dock that stays
    /// shown is a shelf along its top; an auto-hiding one is a walk along the
    /// screen's bottom edge that rises onto the Dock while it is shown.
    static func shelf(_ reading: DockReading, screens: [CGRect], isFullScreen: (CGRect) -> Bool = { _ in false }) -> DockShelf? {
        guard let shelf = shelf(reading, screens: screens), !isFullScreen(shelf.screen) else { return nil }
        return shelf
    }

    private static func shelf(_ reading: DockReading, screens: [CGRect]) -> DockShelf? {
        guard reading.orientation == .bottom, let frame = reading.listFrame else { return nil }
        if reading.autoHides { return autoHidingShelf(frame, screens: screens) }
        guard let screen = screens.first(where: { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }) else { return nil }
        return shelf(on: screen, ground: frame.maxY, walkable: (frame.minX + edgeInset)...(frame.maxX - edgeInset))
    }

    /// A hidden Dock lies just below its screen, so the screen is the one
    /// whose bottom edge the list's frame lies within a Dock's height of.
    private static func autoHidingShelf(_ frame: CGRect, screens: [CGRect]) -> DockShelf? {
        let screen = screens.first {
            frame.maxY >= $0.minY && frame.minY <= $0.minY + frame.height && ($0.minX..<$0.maxX).contains(frame.midX)
        }
        guard let screen else { return nil }
        let slide: AutoHidingDock.Slide = frame.minY >= screen.minY ? .shown : frame.maxY <= screen.minY ? .hidden : .sliding
        let top = slide == .shown ? frame.maxY : screen.minY + shownLift + frame.height
        let dock = AutoHidingDock(span: frame.minX...frame.maxX, top: top, slide: slide)
        let margin = edgeInset + screenMargin
        return shelf(on: screen, ground: screen.minY, walkable: (screen.minX + margin)...(screen.maxX - margin), autoHide: dock)
    }

    private static func shelf(on screen: CGRect, ground: CGFloat, walkable: ClosedRange<CGFloat>, autoHide: AutoHidingDock? = nil) -> DockShelf? {
        guard walkable.upperBound - walkable.lowerBound >= minimumWalk else { return nil }
        return DockShelf(screen: screen, ground: ground, walkable: walkable, autoHide: autoHide)
    }

    /// Accessibility reports frames from the primary display's top-left
    /// corner with y downwards; AppKit measures from its bottom-left with y up.
    static func appKitFrame(axPosition: CGPoint, size: CGSize, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: axPosition.x, y: primaryHeight - axPosition.y - size.height, width: size.width, height: size.height)
    }
}

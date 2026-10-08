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

/// The top of a visible bottom Dock, where the creature can walk.
struct DockShelf: Sendable, Equatable {
    /// The frame of the screen the Dock is on.
    let screen: CGRect
    /// The Dock's top edge in global screen coordinates, where the creature's feet go.
    let top: CGFloat
    /// Where the creature's centre may stand, in global x.
    let walkable: ClosedRange<CGFloat>

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

    /// The window the creature walks in: as wide as the Dock, its bottom on
    /// the Dock's top edge, and tall enough above the box for a hop.
    var panel: CGRect {
        CGRect(
            x: walkable.lowerBound - DockGeometry.edgeInset,
            y: top,
            width: walkable.upperBound - walkable.lowerBound + 2 * DockGeometry.edgeInset,
            height: 2 * Self.spriteSide
        )
    }

    /// The creature's centre in global screen coordinates, `x` points along the Dock.
    func spriteCentre(x: Double) -> CGPoint {
        CGPoint(x: centreX + x, y: top + Self.spriteSide / 2)
    }
}

enum DockGeometry {
    /// Half the creature's collapsed width, so it never hangs off the Dock's ends.
    static let edgeInset: CGFloat = NotchGeometry.peekHeight / 2
    /// A Dock with less room than this to walk is not worth stepping onto.
    static let minimumWalk: CGFloat = 80

    /// Nil unless the Dock sits visibly at the bottom of one of `screens`
    /// with room to walk. A hidden Dock lies off its screen, so a Dock that
    /// reports auto-hide is ruled out before its frame is trusted.
    static func shelf(_ reading: DockReading, screens: [CGRect]) -> DockShelf? {
        guard reading.orientation == .bottom, !reading.autoHides, let frame = reading.listFrame else { return nil }
        guard let screen = screens.first(where: { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }) else { return nil }
        let walkable = (frame.minX + edgeInset)...(frame.maxX - edgeInset)
        guard walkable.upperBound - walkable.lowerBound >= minimumWalk else { return nil }
        return DockShelf(screen: screen, top: frame.maxY, walkable: walkable)
    }

    /// Accessibility reports frames from the primary display's top-left
    /// corner with y downwards; AppKit measures from its bottom-left with y up.
    static func appKitFrame(axPosition: CGPoint, size: CGSize, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: axPosition.x, y: primaryHeight - axPosition.y - size.height, width: size.width, height: size.height)
    }
}

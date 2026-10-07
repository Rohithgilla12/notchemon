import Foundation

/// Facing directions in the row order PMD sheets use.
enum PMDFacing: Int, Sendable, CaseIterable {
    case down, downRight, right, upRight, up, upLeft, left, downLeft

    /// Vectors shorter than this are treated as "on top of the sprite".
    static let deadZone: Double = 0.5

    /// Maps a vector from the sprite to a target onto the nearest facing.
    /// `dy` follows AppKit screen space, where positive y points up.
    static func toward(dx: Double, dy: Double) -> PMDFacing {
        guard (dx * dx + dy * dy).squareRoot() >= deadZone else { return .down }
        let degrees = atan2(dy, dx) * 180 / .pi
        // Rows run counter-clockwise from straight down in 45 degree steps.
        let step = Int(((degrees + 90) / 45).rounded())
        let row = ((step % 8) + 8) % 8
        return PMDFacing(rawValue: row) ?? .down
    }
}

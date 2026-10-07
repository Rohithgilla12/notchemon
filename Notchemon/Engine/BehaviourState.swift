import Foundation

enum Celebration: Sendable, Equatable {
    case levelUp(Int)
    case evolution(from: Int, to: Int)
}

enum Behaviour: Sendable, Equatable {
    case idle
    /// `gaze` is -1 (look left) ... 1 (look right).
    case watching(gaze: Double)
    case sleeping
    case holding
    case celebrating(Celebration)

    var spriteState: SpriteState {
        switch self {
        case .idle, .watching: .idle
        case .sleeping: .sleeping
        case .holding: .happy
        case .celebrating: .levelUp
        }
    }
}

/// Everything the behaviour depends on, sampled at one instant.
struct BehaviourInputs: Sendable, Equatable {
    var secondsSinceInput: TimeInterval
    /// Horizontal offset of the cursor from the sprite centre, when within range.
    var cursorOffsetX: Double?
    var secondsSinceCursorNear: TimeInterval
    var stashCount: Int
    var celebration: Celebration?
    var sleepEnabled: Bool
}

/// Behaviour is a pure function of its inputs; there is no hidden transition
/// history, so the engine can resample at any time and converge.
enum BehaviourRules {
    static let sleepAfter: TimeInterval = 10 * 60
    static let watchRadius: Double = 150
    static let watchLinger: TimeInterval = 2

    static func resolve(_ input: BehaviourInputs) -> Behaviour {
        if let celebration = input.celebration { return .celebrating(celebration) }
        if input.sleepEnabled, input.secondsSinceInput >= sleepAfter { return .sleeping }
        if let dx = input.cursorOffsetX {
            return .watching(gaze: max(-1, min(1, dx / watchRadius)))
        }
        if input.secondsSinceCursorNear < watchLinger { return .watching(gaze: 0) }
        if input.stashCount > 0 { return .holding }
        return .idle
    }
}

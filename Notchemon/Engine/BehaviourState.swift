import Foundation

enum Celebration: Sendable, Equatable {
    case levelUp(Int)
    case evolution(from: Int, to: Int)
}

enum Behaviour: Sendable, Equatable {
    case idle
    case watching(facing: Facing)
    case sleeping
    case holding
    case celebrating(Celebration)

    var facing: Facing {
        if case .watching(let facing) = self { facing } else { .down }
    }
}

/// The cursor relative to the sprite centre, in screen points with y up.
struct CursorOffset: Sendable, Equatable {
    var dx: Double
    var dy: Double
}

/// Everything the behaviour depends on, sampled at one instant.
struct BehaviourInputs: Sendable, Equatable {
    var secondsSinceInput: TimeInterval
    /// Present only while the cursor is within `BehaviourRules.watchRadius`.
    var cursorOffset: CursorOffset?
    var secondsSinceCursorNear: TimeInterval
    var stashCount: Int
    var celebration: Celebration?
    var sleepEnabled: Bool
    var sleepAfter: TimeInterval = BehaviourRules.sleepAfter
}

/// Behaviour is a pure function of its inputs; there is no hidden transition
/// history, so the engine can resample at any time and converge.
enum BehaviourRules {
    static let sleepAfter: TimeInterval = 10 * 60
    static let watchRadius: Double = 150
    static let watchLinger: TimeInterval = 2

    static func resolve(_ input: BehaviourInputs) -> Behaviour {
        if let celebration = input.celebration { return .celebrating(celebration) }
        if input.sleepEnabled, input.secondsSinceInput >= input.sleepAfter { return .sleeping }
        if let offset = input.cursorOffset {
            return .watching(facing: facing(toward: offset))
        }
        if input.secondsSinceCursorNear < watchLinger { return .watching(facing: .down) }
        if input.stashCount > 0 { return .holding }
        return .idle
    }

    static func facing(toward offset: CursorOffset) -> Facing {
        Facing.toward(dx: offset.dx, dy: offset.dy).frontFacing
    }
}

/// Something that interrupts the loop with a one-shot animation.
enum SpriteCue: Sendable, Equatable {
    case behaviourChanged(from: Behaviour, to: Behaviour)
    case cursorEnteredNotch(panelExpanded: Bool)
}

/// The single place that decides which animation plays when.
enum SpriteChoreography {
    static func loop(for behaviour: Behaviour) -> SpriteState {
        switch behaviour {
        case .sleeping: .sleeping
        // Stash icons already show holding, and celebrating is a one-shot
        // over whatever loop the creature returns to.
        case .idle, .watching, .holding, .celebrating: .idle
        }
    }

    /// Which anims are seen in each panel mode, so each mode sizes and stands
    /// the creature for those alone. The hop greets a cursor arriving at the
    /// closed notch, and its tall arc would shrink the creature in the panel.
    /// Below the notch a sleeping creature is tucked out of sight and pops
    /// out to show it woke, so Sleep and Wake are never seen there.
    static func plays(_ state: SpriteState, panelExpanded: Bool) -> Bool {
        switch state {
        case .idle, .celebrating: true
        case .hop: !panelExpanded
        case .sleeping, .wake: panelExpanded
        }
    }

    static func oneShot(for cue: SpriteCue) -> SpriteState? {
        switch cue {
        case .cursorEnteredNotch(let panelExpanded):
            plays(.hop, panelExpanded: panelExpanded) ? .hop : nil
        case .behaviourChanged(let previous, .celebrating(let celebration)) where previous != .celebrating(celebration):
            .celebrating
        case .behaviourChanged(.sleeping, let next) where next != .sleeping:
            .wake
        case .behaviourChanged:
            nil
        }
    }
}

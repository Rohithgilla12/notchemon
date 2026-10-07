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

/// Whether the cursor was within `BehaviourRules.watchRadius` of the
/// creature, and in which panel mode that was measured.
struct CursorProximity: Sendable, Equatable {
    var near: Bool
    var panelExpanded: Bool
}

/// When the creature notices the cursor and hops.
enum HopCue {
    /// Jiggling the cursor across the radius's edge greets it once.
    static let cooldown: TimeInterval = 4

    /// The creature hops when the cursor crosses into the watch radius while
    /// the panel is closed, before a hover over the notch can open it. A
    /// panel opening or closing moves the creature, not the cursor, so the
    /// creature notices nothing then.
    static func hops(
        from previous: CursorProximity?, to current: CursorProximity, secondsSinceLastHop: TimeInterval, enabled: Bool
    ) -> Bool {
        guard enabled, let previous, previous.panelExpanded == current.panelExpanded else { return false }
        return !current.panelExpanded && !previous.near && current.near && secondsSinceLastHop >= cooldown
    }
}

/// Something that interrupts the loop with a one-shot animation.
enum SpriteCue: Sendable, Equatable {
    case behaviourChanged(from: Behaviour, to: Behaviour)
    case cursorNoticed
}

/// How the renderer plays a loop's frames.
enum LoopPlayback: Sendable, Equatable {
    /// Every frame in turn, forever.
    case cycle
    /// The rest frame alone, so the creature stays put. A fidget plays the
    /// whole loop once.
    case hold
}

/// A loop anim and how it plays.
struct LoopChoice: Sendable, Equatable {
    let state: SpriteState
    let playback: LoopPlayback
}

/// The single place that decides which animation plays when.
enum SpriteChoreography {
    /// The loops that can show a behaviour in a style, best first. The
    /// creature plays the first its provider has art for; the last always
    /// exists. Stash icons already show holding, and celebrating is a
    /// one-shot over whatever loop the creature returns to, so both pass the
    /// time like idle.
    static func loops(for behaviour: Behaviour, style: IdleStyle) -> [LoopChoice] {
        if behaviour == .sleeping { return [LoopChoice(state: .sleeping, playback: .cycle)] }
        let calm = LoopChoice(state: .idle, playback: .hold)
        return switch style {
        case .calm: [calm]
        case .lively: [LoopChoice(state: .idle, playback: .cycle)]
        // Lying down is one still frame where the art exists; holding it
        // keeps a busier lying anim just as still.
        case .sitting: [LoopChoice(state: .sitting, playback: .hold), calm]
        }
    }

    /// The frame a held loop shows: the one the anim lingers on longest,
    /// the earliest of those on a tie.
    static func restFrame(_ durations: [TimeInterval]) -> Int {
        durations.max().flatMap { durations.firstIndex(of: $0) } ?? 0
    }

    /// Which anims are seen in each panel mode, so each mode sizes and stands
    /// the creature for those alone. The hop greets a cursor arriving at the
    /// closed notch, and its tall arc would shrink the creature in the panel.
    /// Below the notch a sleeping creature is tucked out of sight and pops
    /// out to show it woke, so Sleep and Wake are never seen there. The
    /// creature walks only along the strip below the closed notch. A lying
    /// creature's tail can hang well below its ground point, so the sitting
    /// anim counts only in the style that shows it, and the other styles keep
    /// their ground line.
    static func plays(_ state: SpriteState, panelExpanded: Bool, style: IdleStyle) -> Bool {
        switch state {
        case .idle, .celebrating: true
        case .sitting: style == .sitting
        case .hop, .walking: !panelExpanded
        case .sleeping, .wake: panelExpanded
        }
    }

    static func oneShot(for cue: SpriteCue) -> SpriteState? {
        switch cue {
        case .cursorNoticed:
            .hop
        case .behaviourChanged(let previous, .celebrating(let celebration)) where previous != .celebrating(celebration):
            .celebrating
        case .behaviourChanged(.sleeping, let next) where next != .sleeping:
            .wake
        case .behaviourChanged:
            nil
        }
    }
}

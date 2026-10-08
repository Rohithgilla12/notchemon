import Foundation

/// One straight walk at a steady pace. Positions here and in `RoamPhase` are
/// x offsets in points from the notch centre, rightwards positive.
struct RoamWalk: Sendable, Equatable {
    let from: Double
    let to: Double
    let start: Date
    /// Points per second.
    let speed: Double

    var duration: TimeInterval { abs(to - from) / speed }
    var end: Date { start + duration }
    var direction: Facing { to < from ? .left : .right }

    func x(at now: Date) -> Double {
        guard duration > 0 else { return to }
        let progress = min(max(now.timeIntervalSince(start) / duration, 0), 1)
        return from + (to - from) * progress
    }
}

/// Where the creature is along the strip below the menu bar. Every phase
/// gives its position at any instant, so nothing has to tick while it walks.
enum RoamPhase: Sendable, Equatable {
    /// Under the notch, kept there by `Homing`.
    case home
    case resting(at: Double, until: Date)
    /// On the way to a spot to rest at.
    case walking(RoamWalk)
    /// On the way home, to stay there.
    case returning(RoamWalk)

    func x(at now: Date) -> Double {
        switch self {
        case .home: 0
        case .resting(let x, _): x
        case .walking(let walk), .returning(let walk): walk.x(at: now)
        }
    }

    var walk: RoamWalk? {
        switch self {
        case .walking(let walk), .returning(let walk): walk
        case .home, .resting: nil
        }
    }

    /// The most this phase takes the creature from home, so the window can
    /// keep all of it in view.
    var farthest: Double {
        switch self {
        case .home: 0
        case .resting(let x, _): abs(x)
        case .walking(let walk), .returning(let walk): max(abs(walk.from), abs(walk.to))
        }
    }

    /// When the phase ends by itself. Home ends only when the inputs change.
    var deadline: Date? {
        switch self {
        case .home: nil
        case .resting(_, let until): until
        case .walking(let walk), .returning(let walk): walk.end
        }
    }
}

/// Whether the creature may wander, and if not, how it gets home.
enum Homing: Sendable, Equatable {
    case free
    case walk
    /// Hurries home to greet the cursor.
    case run
    /// Is home at once, because the strip is not where the creature is shown.
    case snap
}

/// Everything that can call the creature home.
struct HomingConditions: Sendable, Equatable {
    var wander: WanderRange
    /// Expanded by hover, the hotkey, or onboarding.
    var panelOpen: Bool
    var sleeping: Bool
    var focusing: Bool
    var fullScreen: Bool
    /// The cursor is within `BehaviourRules.watchRadius` of the creature's home.
    var cursorNearHome: Bool
    /// False until a starter is chosen.
    var hasCreature: Bool
}

struct RoamInputs: Sendable, Equatable {
    var now: Date
    /// Where the creature may stand. Always contains home.
    var range: ClosedRange<Double>
    var homing: Homing
}

/// Wandering is a function of the current phase and inputs: the caller asks
/// again at the phase's deadline or whenever an input changes, and asking
/// with nothing due returns the phase unchanged.
enum RoamRules {
    static let rest: ClosedRange<TimeInterval> = 4...15
    static let minimumStride: Double = 60
    static let walkSpeed: Double = 35
    static let runSpeed: Double = 70
    /// How often a walk from a resting spot heads back to rest at home.
    static let homeChance = 0.25

    static func homing(_ conditions: HomingConditions) -> Homing {
        if conditions.panelOpen || conditions.fullScreen || !conditions.hasCreature { return .snap }
        if conditions.cursorNearHome { return .run }
        if conditions.wander == .off || conditions.sleeping || conditions.focusing { return .walk }
        return .free
    }

    static func next(_ phase: RoamPhase, _ inputs: RoamInputs, using rng: inout some RandomNumberGenerator) -> RoamPhase {
        let now = inputs.now
        switch inputs.homing {
        case .snap:
            return .home
        case .walk, .run:
            let speed = inputs.homing == .run ? runSpeed : walkSpeed
            switch phase {
            case .home:
                return .home
            case .returning(let walk) where walk.speed == speed:
                return now >= walk.end ? .home : phase
            case .resting, .walking, .returning:
                let x = phase.x(at: now)
                return x == 0 ? .home : .returning(RoamWalk(from: x, to: 0, start: now, speed: speed))
            }
        case .free:
            return wander(phase, inputs, using: &rng)
        }
    }

    private static func wander(_ phase: RoamPhase, _ inputs: RoamInputs, using rng: inout some RandomNumberGenerator) -> RoamPhase {
        let now = inputs.now
        let range = inputs.range
        switch phase {
        case .home:
            return .resting(at: 0, until: now + .random(in: rest, using: &rng))
        case .resting(let x, let until):
            guard range.contains(x) else { return walkBack(from: x, inputs) }
            return now < until ? phase : stroll(from: x, inputs, using: &rng)
        case .walking(let walk), .returning(let walk):
            guard range.contains(walk.to) else {
                let x = walk.x(at: now)
                return range.contains(x) ? .resting(at: x, until: now + .random(in: rest, using: &rng)) : walkBack(from: x, inputs)
            }
            return now < walk.end ? .walking(walk) : .resting(at: walk.to, until: now + .random(in: rest, using: &rng))
        }
    }

    /// The range narrowed past the creature, so it walks in to the nearest edge.
    private static func walkBack(from x: Double, _ inputs: RoamInputs) -> RoamPhase {
        .walking(RoamWalk(from: x, to: x.clamped(to: inputs.range), start: inputs.now, speed: walkSpeed))
    }

    private static func stroll(from x: Double, _ inputs: RoamInputs, using rng: inout some RandomNumberGenerator) -> RoamPhase {
        let headsHome = abs(x) >= minimumStride && Double.random(in: 0..<1, using: &rng) < homeChance
        guard let target = headsHome ? 0 : target(from: x, in: inputs.range, using: &rng) else {
            return .resting(at: x, until: inputs.now + .random(in: rest, using: &rng))
        }
        return .walking(RoamWalk(from: x, to: target, start: inputs.now, speed: walkSpeed))
    }

    /// Anywhere in range at least `minimumStride` away, or nil when the range
    /// is too narrow for that.
    private static func target(from x: Double, in range: ClosedRange<Double>, using rng: inout some RandomNumberGenerator) -> Double? {
        let left = max(0, x - minimumStride - range.lowerBound)
        let right = max(0, range.upperBound - x - minimumStride)
        guard left + right > 0 else { return nil }
        let pick = Double.random(in: 0..<(left + right), using: &rng)
        return pick < left ? range.lowerBound + pick : x + minimumStride + pick - left
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

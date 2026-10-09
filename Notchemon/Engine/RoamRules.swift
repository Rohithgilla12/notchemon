import Foundation

/// What the creature walks along.
enum Perch: Sendable, Equatable {
    /// The strip below the menu bar, where home is.
    case topEdge
    /// The top of the Dock.
    case dock
}

/// Where the creature stands. On the top edge x is in points from the notch
/// centre; on the Dock it is from the middle of the Dock's shelf. Either
/// way rightwards is positive.
struct RoamSpot: Sendable, Equatable {
    var perch: Perch
    var x: Double

    static let home = RoamSpot(perch: .topEdge, x: 0)
    static func topEdge(_ x: Double) -> RoamSpot { RoamSpot(perch: .topEdge, x: x) }
    static func dock(_ x: Double) -> RoamSpot { RoamSpot(perch: .dock, x: x) }
}

/// One straight walk along one perch at a steady pace.
struct RoamWalk: Sendable, Equatable {
    let perch: Perch
    let from: Double
    let to: Double
    let start: Date
    /// Points per second.
    let speed: Double

    init(on perch: Perch, from: Double, to: Double, start: Date, speed: Double) {
        self.perch = perch
        self.from = from
        self.to = to
        self.start = start
        self.speed = speed
    }

    var duration: TimeInterval { abs(to - from) / speed }
    var end: Date { start + duration }
    var direction: Facing { to < from ? .left : .right }

    func x(at now: Date) -> Double {
        guard duration > 0 else { return to }
        let progress = min(max(now.timeIntervalSince(start) / duration, 0), 1)
        return from + (to - from) * progress
    }

    /// When this walk carries the creature's centre into and out of the
    /// circle of `radius` around `cursor`, which is measured from the centre
    /// at x 0 on this walk's perch, in order. A walk that starts inside only
    /// leaves: the cursor was already measured where the walk set off.
    func crossings(of cursor: CursorOffset, radius: Double) -> [Date] {
        let span = radius * radius - cursor.dy * cursor.dy
        guard span > 0, duration > 0 else { return [] }
        let halfChord = span.squareRoot()
        let edges: [Double] = [cursor.dx - halfChord, cursor.dx + halfChord]
        let offsets: [TimeInterval] = edges.map { (edge: Double) -> TimeInterval in
            (edge - from) / (to - from) * duration
        }
        let during: [TimeInterval] = offsets.filter { $0 > 0 && $0 < duration }.sorted()
        return during.map { (offset: TimeInterval) -> Date in start + offset }
    }
}

/// Where the creature is and what it is doing there. Every phase gives its
/// spot at any instant, so nothing has to tick while it moves.
enum RoamPhase: Sendable, Equatable {
    /// Under the notch, kept there by `Homing`.
    case home
    case resting(at: RoamSpot, until: Date)
    /// Held where it stopped, away from home, while `Homing.stay` lasts.
    /// It rests there afterwards.
    case stopped(at: RoamSpot)
    /// On the way to a spot to rest at.
    case walking(RoamWalk)
    /// On the way home along the top edge, to stay there.
    case returning(RoamWalk)
    /// Hopping out at `from` and, `RoamRules.transferHalf` later, in at `to`
    /// on the other perch.
    case transferring(from: RoamSpot, to: RoamSpot, start: Date)

    func spot(at now: Date) -> RoamSpot {
        switch self {
        case .home: .home
        case .resting(let spot, _), .stopped(let spot): spot
        case .walking(let walk), .returning(let walk): RoamSpot(perch: walk.perch, x: walk.x(at: now))
        case .transferring(let from, let to, let start): now < start + RoamRules.transferHalf ? from : to
        }
    }

    /// Where `Homing.stay` leaves the creature: the landing spot of a hop
    /// under way, which cannot be taken back, else where it is now.
    func heldSpot(at now: Date) -> RoamSpot {
        if case .transferring(_, let to, _) = self { return to }
        return spot(at: now)
    }

    /// The perch the creature is on, or is hopping to.
    var perch: Perch {
        switch self {
        case .home: .topEdge
        case .resting(let spot, _), .stopped(let spot), .transferring(_, let spot, _): spot.perch
        case .walking(let walk), .returning(let walk): walk.perch
        }
    }

    /// Whether the creature shows on `perch` at any point in this phase.
    func touches(_ perch: Perch) -> Bool {
        if case .transferring(let from, let to, _) = self { return from.perch == perch || to.perch == perch }
        return self.perch == perch
    }

    var walk: RoamWalk? {
        switch self {
        case .walking(let walk), .returning(let walk): walk
        case .home, .resting, .stopped, .transferring: nil
        }
    }

    /// The most this phase takes the creature from home along the top edge,
    /// so the notch window can keep all of it in view.
    var farthestAlongTopEdge: Double {
        switch self {
        case .home: 0
        case .resting(let spot, _), .stopped(let spot): spot.perch == .topEdge ? abs(spot.x) : 0
        case .walking(let walk), .returning(let walk): walk.perch == .topEdge ? max(abs(walk.from), abs(walk.to)) : 0
        case .transferring(let from, let to, _): [from, to].filter { $0.perch == .topEdge }.map { abs($0.x) }.max() ?? 0
        }
    }

    /// When the phase ends by itself. Home and a stop end only when the
    /// inputs change.
    var deadline: Date? {
        switch self {
        case .home, .stopped: nil
        case .resting(_, let until): until
        case .walking(let walk), .returning(let walk): walk.end
        case .transferring(_, _, let start): start + 2 * RoamRules.transferHalf
        }
    }
}

/// Whether the creature may wander, and if not, how it gets home or that it
/// stays put.
enum Homing: Sendable, Equatable {
    case free
    /// Stops where it is, because it fell asleep or a wild creature is visiting.
    case stay
    case walk
    /// Hurries home to greet the cursor.
    case run
    /// Is home at once, because the strip is not where the creature is shown.
    case snap
}

/// Everything that can call the creature home or hold it where it is.
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
    /// Where the creature is, or is hopping to.
    var perch: Perch
    /// A wild creature is visiting, which the partner stops to watch.
    var visitor = false
}

struct RoamInputs: Sendable, Equatable {
    var now: Date
    /// Where the creature may stand on the top edge. Always contains home.
    var range: ClosedRange<Double>
    /// Where it may stand on the Dock, or nil when it may not go there.
    var dock: ClosedRange<Double>? = nil
    var homing: Homing

    func range(of perch: Perch) -> ClosedRange<Double>? {
        switch perch {
        case .topEdge: range
        case .dock: dock
        }
    }
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
    /// How often a finished rest hops to the other perch instead of walking,
    /// when both perches are open.
    static let transferChance = 0.25
    /// How long the hop out takes, and then the hop in.
    static let transferHalf: TimeInterval = 0.35

    static func homing(_ conditions: HomingConditions) -> Homing {
        if conditions.panelOpen || conditions.fullScreen || !conditions.hasCreature { return .snap }
        // Asleep it stays put even for a cursor at home: moving the mouse
        // wakes it within a second, and then it runs to greet it.
        if conditions.sleeping { return .stay }
        // Held, it can never walk into the visitor's path.
        if conditions.visitor { return .stay }
        // From the Dock a cursor at the notch is far from the creature, not a greeting.
        if conditions.cursorNearHome, conditions.perch == .topEdge { return .run }
        if conditions.wander == .off || conditions.focusing { return .walk }
        return .free
    }

    static func next(_ phase: RoamPhase, _ inputs: RoamInputs, using rng: inout some RandomNumberGenerator) -> RoamPhase {
        let now = inputs.now
        if case .transferring(_, let to, _) = phase {
            // A hop under way finishes unless it lands on a Dock that has
            // gone; the hop out cannot be taken back.
            if inputs.homing == .snap || inputs.range(of: to.perch) == nil { return .home }
            guard let deadline = phase.deadline, now >= deadline else { return phase }
            return next(.resting(at: to, until: now + .random(in: rest, using: &rng)), inputs, using: &rng)
        }
        switch inputs.homing {
        case .snap:
            return .home
        case .stay:
            let spot = phase.spot(at: now)
            guard spot != .home, let range = inputs.range(of: spot.perch) else { return .home }
            // A range that narrows past a sleeper moves it to the new end
            // rather than waking it to walk there.
            return .stopped(at: RoamSpot(perch: spot.perch, x: spot.x.clamped(to: range)))
        case .walk, .run:
            return goHome(phase, inputs, speed: inputs.homing == .run ? runSpeed : walkSpeed, using: &rng)
        case .free:
            return wander(phase, inputs, using: &rng)
        }
    }

    /// Home is on the top edge, so from the Dock the creature hops up first.
    private static func goHome(_ phase: RoamPhase, _ inputs: RoamInputs, speed: Double, using rng: inout some RandomNumberGenerator) -> RoamPhase {
        let now = inputs.now
        let spot = phase.spot(at: now)
        if spot.perch == .dock { return transfer(from: spot, to: .topEdge, inputs, using: &rng) }
        switch phase {
        case .home:
            return .home
        case .returning(let walk) where walk.speed == speed:
            return now >= walk.end ? .home : phase
        case .resting, .stopped, .walking, .returning, .transferring:
            return spot.x == 0 ? .home : .returning(RoamWalk(on: .topEdge, from: spot.x, to: 0, start: now, speed: speed))
        }
    }

    private static func wander(_ phase: RoamPhase, _ inputs: RoamInputs, using rng: inout some RandomNumberGenerator) -> RoamPhase {
        let now = inputs.now
        let spot = phase.spot(at: now)
        // The Dock went away under the creature, so it hops up to the top edge.
        guard let range = inputs.range(of: spot.perch) else { return transfer(from: spot, to: .topEdge, inputs, using: &rng) }
        switch phase {
        case .home:
            return .resting(at: .home, until: now + .random(in: rest, using: &rng))
        case .stopped:
            guard range.contains(spot.x) else { return walkBack(from: spot, to: range, at: now) }
            return .resting(at: spot, until: now + .random(in: rest, using: &rng))
        case .resting(_, let until):
            guard range.contains(spot.x) else { return walkBack(from: spot, to: range, at: now) }
            return now < until ? phase : afterRest(at: spot, in: range, inputs, using: &rng)
        case .walking(let walk), .returning(let walk):
            guard range.contains(walk.to) else {
                return range.contains(spot.x) ? .resting(at: spot, until: now + .random(in: rest, using: &rng)) : walkBack(from: spot, to: range, at: now)
            }
            return now < walk.end ? .walking(walk) : .resting(at: RoamSpot(perch: walk.perch, x: walk.to), until: now + .random(in: rest, using: &rng))
        case .transferring:
            return phase
        }
    }

    /// What moving from `old` to `new` at `now` did, for the stats: a walk
    /// that ended or was cut short counts the ground it covered, and a hop
    /// to the other perch counts once as it sets off.
    static func events(from old: RoamPhase, to new: RoamPhase, at now: Date) -> [CompanionEvent] {
        var events: [CompanionEvent] = []
        if let walk = old.walk, new.walk != walk {
            let points: Double = abs(walk.x(at: now) - walk.from)
            if points > 0 { events.append(.walked(points: points, perch: walk.perch)) }
        }
        if case .transferring(_, let to, _) = new, new != old {
            events.append(.transferred(to: to.perch))
        }
        return events
    }

    /// The range narrowed past the creature, so it walks in to the nearest edge.
    private static func walkBack(from spot: RoamSpot, to range: ClosedRange<Double>, at now: Date) -> RoamPhase {
        .walking(RoamWalk(on: spot.perch, from: spot.x, to: spot.x.clamped(to: range), start: now, speed: walkSpeed))
    }

    /// With both perches open it sometimes hops across, and always does when
    /// its own perch has no room for a stride.
    private static func afterRest(at spot: RoamSpot, in range: ClosedRange<Double>, _ inputs: RoamInputs, using rng: inout some RandomNumberGenerator) -> RoamPhase {
        let other: Perch = spot.perch == .topEdge ? .dock : .topEdge
        if inputs.range(of: other) != nil {
            let cramped = room(from: spot.x, in: range) == nil
            if cramped || Double.random(in: 0..<1, using: &rng) < transferChance {
                return transfer(from: spot, to: other, inputs, using: &rng)
            }
        }
        return stroll(from: spot, in: range, inputs, using: &rng)
    }

    /// Lands anywhere on `perch`, which is open: the top edge always is.
    private static func transfer(from spot: RoamSpot, to perch: Perch, _ inputs: RoamInputs, using rng: inout some RandomNumberGenerator) -> RoamPhase {
        let range = inputs.range(of: perch) ?? 0...0
        let landing = RoamSpot(perch: perch, x: .random(in: range, using: &rng))
        return .transferring(from: spot, to: landing, start: inputs.now)
    }

    /// Only the top edge has home on it to head back to.
    private static func stroll(from spot: RoamSpot, in range: ClosedRange<Double>, _ inputs: RoamInputs, using rng: inout some RandomNumberGenerator) -> RoamPhase {
        let x = spot.x
        let headsHome = spot.perch == .topEdge && abs(x) >= minimumStride && Double.random(in: 0..<1, using: &rng) < homeChance
        guard let target = headsHome ? 0 : target(from: x, in: range, using: &rng) else {
            return .resting(at: spot, until: inputs.now + .random(in: rest, using: &rng))
        }
        return .walking(RoamWalk(on: spot.perch, from: x, to: target, start: inputs.now, speed: walkSpeed))
    }

    /// How much of `range` lies at least `minimumStride` away on the left and
    /// on the right, or nil when there is none.
    private static func room(from x: Double, in range: ClosedRange<Double>) -> (left: Double, right: Double)? {
        let left = max(0, x - minimumStride - range.lowerBound)
        let right = max(0, range.upperBound - x - minimumStride)
        return left + right > 0 ? (left, right) : nil
    }

    /// Anywhere in range at least `minimumStride` away, or nil when the range
    /// is too narrow for that.
    private static func target(from x: Double, in range: ClosedRange<Double>, using rng: inout some RandomNumberGenerator) -> Double? {
        guard let (left, right) = room(from: x, in: range) else { return nil }
        let pick = Double.random(in: 0..<(left + right), using: &rng)
        return pick < left ? range.lowerBound + pick : x + minimumStride + pick - left
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

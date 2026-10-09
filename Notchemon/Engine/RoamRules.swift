import Foundation
import os

/// Each party member's phase changes, at debug level. Read with
/// `log show --debug --predicate 'subsystem == "com.rohithgilla.Notchemon" && category == "roam"'`.
let roamLog = Logger(subsystem: "com.rohithgilla.Notchemon", category: "roam")

/// A small seedable generator, so each roamer, and each test, replays its own draws.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

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
    /// False for a follower, which only the leader's sleep, a visitor, full
    /// screen, and Wander set to Off hold or send in.
    var leads = true
}

struct RoamInputs: Sendable, Equatable {
    var now: Date
    /// Where the creature may stand on the top edge. Always contains home.
    var range: ClosedRange<Double>
    /// Where it may stand on the Dock, or nil when it may not go there.
    var dock: ClosedRange<Double>? = nil
    var homing: Homing
    /// Where the rest of the party stands or is headed on each perch, each
    /// spot padded by `RoamRules.gap`. New walk targets, rests, and landings
    /// keep out of these spans.
    var occupied: [Perch: [ClosedRange<Double>]] = [:]
    /// A follower is out of sight at home, where the leader stands, and
    /// hops out of it rather than resting or walking out from there.
    var follower = false

    func range(of perch: Perch) -> ClosedRange<Double>? {
        switch perch {
        case .topEdge: range
        case .dock: dock
        }
    }

    /// A spot on a span's edge is clear, so a creature can step to the edge and stay.
    func isFree(_ spot: RoamSpot) -> Bool {
        !(occupied[spot.perch] ?? []).contains { $0.lowerBound < spot.x && spot.x < $0.upperBound }
    }

    /// The parts of `perch`'s range clear of the rest of the party and of
    /// `also`, or none when the perch is closed.
    func free(on perch: Perch, also: [ClosedRange<Double>] = []) -> [ClosedRange<Double>] {
        guard let range = range(of: perch) else { return [] }
        return range.subtracting((occupied[perch] ?? []) + also)
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
    /// How far apart party members' centres stay when they choose where to
    /// go: a sprite's box and a little air.
    static let gap: Double = 60

    static func homing(_ conditions: HomingConditions) -> Homing {
        guard conditions.leads else { return followerHoming(conditions) }
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

    /// A follower never heads home, where the leader stands, so the open
    /// panel, focus, and the cursor leave it wandering. Sent in, it waits
    /// out of sight at home and hops out again when it may.
    private static func followerHoming(_ conditions: HomingConditions) -> Homing {
        if conditions.fullScreen || !conditions.hasCreature || conditions.wander == .off { return .snap }
        if conditions.sleeping || conditions.visitor { return .stay }
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
            if inputs.follower { return emerge(inputs, using: &rng) }
            return .resting(at: .home, until: now + .random(in: rest, using: &rng))
        case .stopped:
            guard range.contains(spot.x) else { return walkBack(from: spot, to: range, at: now) }
            // Stopped mid-walk beside another member, it steps clear on waking.
            guard inputs.isFree(spot) else { return stepClear(from: spot, inputs, using: &rng) }
            return .resting(at: spot, until: now + .random(in: rest, using: &rng))
        case .resting(_, let until):
            guard range.contains(spot.x) else { return walkBack(from: spot, to: range, at: now) }
            guard now >= until else { return phase }
            // A follower that found no room waited out of sight, so it tries hopping out again.
            if inputs.follower, spot == .home { return emerge(inputs, using: &rng) }
            return afterRest(at: spot, inputs, using: &rng)
        case .walking(let walk), .returning(let walk):
            guard range.contains(walk.to) else {
                return range.contains(spot.x) ? .resting(at: spot, until: now + .random(in: rest, using: &rng)) : walkBack(from: spot, to: range, at: now)
            }
            return now < walk.end ? .walking(walk) : .resting(at: RoamSpot(perch: walk.perch, x: walk.to), until: now + .random(in: rest, using: &rng))
        case .transferring:
            return phase
        }
    }

    /// The spans the rest of the party keeps a creature out of: where each
    /// of `others` stands at `now` and where it is headed, padded by `gap`,
    /// and home too for a follower, since the leader comes back to it. A
    /// member at home holds no other ground.
    static func occupied(by others: [RoamPhase], at now: Date, follower: Bool) -> [Perch: [ClosedRange<Double>]] {
        var spots: [RoamSpot] = []
        for phase in others {
            spots.append(phase.spot(at: now))
            if let walk = phase.walk { spots.append(RoamSpot(perch: walk.perch, x: walk.to)) }
            if case .transferring(_, let to, _) = phase { spots.append(to) }
        }
        var spans: [Perch: [ClosedRange<Double>]] = follower ? [.topEdge: [(-gap)...gap]] : [:]
        for spot in spots where spot != .home {
            spans[spot.perch, default: []].append((spot.x - gap)...(spot.x + gap))
        }
        return spans
    }

    /// What party member `partner` moving from `old` to `new` at `now` did,
    /// for the stats: a walk that ended or was cut short counts the ground
    /// it covered, and a hop to the other perch counts once as it sets off.
    static func events(from old: RoamPhase, to new: RoamPhase, at now: Date, partner: Int) -> [CompanionEvent] {
        var events: [CompanionEvent] = []
        if let walk = old.walk, new.walk != walk {
            let points: Double = abs(walk.x(at: now) - walk.from)
            if points > 0 { events.append(.walked(points: points, perch: walk.perch, partner: partner)) }
        }
        if case .transferring(let from, let to, _) = new, new != old, from.perch != to.perch {
            events.append(.transferred(to: to.perch, partner: partner))
        }
        return events
    }

    /// The range narrowed past the creature, so it walks in to the nearest edge.
    private static func walkBack(from spot: RoamSpot, to range: ClosedRange<Double>, at now: Date) -> RoamPhase {
        .walking(RoamWalk(on: spot.perch, from: spot.x, to: spot.x.clamped(to: range), start: now, speed: walkSpeed))
    }

    /// With both perches open it sometimes hops across, and always does when
    /// its own perch has no room for a stride. It never hops to a perch with
    /// no clear spot to land on.
    private static func afterRest(at spot: RoamSpot, _ inputs: RoamInputs, using rng: inout some RandomNumberGenerator) -> RoamPhase {
        let other: Perch = spot.perch == .topEdge ? .dock : .topEdge
        if !inputs.free(on: other).isEmpty {
            let cramped = targets(from: spot, inputs).isEmpty
            if cramped || Double.random(in: 0..<1, using: &rng) < transferChance {
                return transfer(from: spot, to: other, inputs, using: &rng)
            }
        }
        return stroll(from: spot, inputs, using: &rng)
    }

    /// Lands anywhere on `perch` clear of the party. With no clear spot,
    /// which only a creature that must leave its perch meets, a follower
    /// drops out of sight at home and anyone else lands anywhere on it. The
    /// top edge is always open.
    private static func transfer(from spot: RoamSpot, to perch: Perch, _ inputs: RoamInputs, using rng: inout some RandomNumberGenerator) -> RoamPhase {
        let range = inputs.range(of: perch) ?? 0...0
        let alone = inputs.occupied[perch]?.isEmpty ?? true
        if !alone, let x = pick(in: inputs.free(on: perch), using: &rng) {
            return .transferring(from: spot, to: RoamSpot(perch: perch, x: x), start: inputs.now)
        }
        let landing: RoamSpot = inputs.follower && perch == .topEdge ? .home : RoamSpot(perch: perch, x: .random(in: range, using: &rng))
        return .transferring(from: spot, to: landing, start: inputs.now)
    }

    /// A follower leaving home hops out to a clear spot on the top edge, else
    /// on the Dock, else waits at home for room.
    private static func emerge(_ inputs: RoamInputs, using rng: inout some RandomNumberGenerator) -> RoamPhase {
        for perch in [Perch.topEdge, .dock] {
            if let x = pick(in: inputs.free(on: perch), using: &rng) {
                return .transferring(from: .home, to: RoamSpot(perch: perch, x: x), start: inputs.now)
            }
        }
        return .resting(at: .home, until: inputs.now + .random(in: rest, using: &rng))
    }

    /// Walks to the nearest clear spot on its perch, else hops to one on the
    /// other perch, else rests where it is.
    private static func stepClear(from spot: RoamSpot, _ inputs: RoamInputs, using rng: inout some RandomNumberGenerator) -> RoamPhase {
        let edges: [Double] = inputs.free(on: spot.perch).map { spot.x.clamped(to: $0) }
        if let nearest = edges.min(by: { abs($0 - spot.x) < abs($1 - spot.x) }) {
            return .walking(RoamWalk(on: spot.perch, from: spot.x, to: nearest, start: inputs.now, speed: walkSpeed))
        }
        let other: Perch = spot.perch == .topEdge ? .dock : .topEdge
        if let x = pick(in: inputs.free(on: other), using: &rng) {
            return .transferring(from: spot, to: RoamSpot(perch: other, x: x), start: inputs.now)
        }
        return .resting(at: spot, until: inputs.now + .random(in: rest, using: &rng))
    }

    /// Only the top edge has home on it to head back to, and only a creature
    /// whose home is clear heads there.
    private static func stroll(from spot: RoamSpot, _ inputs: RoamInputs, using rng: inout some RandomNumberGenerator) -> RoamPhase {
        let x = spot.x
        let headsHome = spot.perch == .topEdge && abs(x) >= minimumStride && inputs.isFree(.home)
            && Double.random(in: 0..<1, using: &rng) < homeChance
        guard let target = headsHome ? 0 : pick(in: targets(from: spot, inputs), using: &rng) else {
            return .resting(at: spot, until: inputs.now + .random(in: rest, using: &rng))
        }
        return .walking(RoamWalk(on: spot.perch, from: x, to: target, start: inputs.now, speed: walkSpeed))
    }

    /// The parts of the perch at least `minimumStride` from `spot` and clear
    /// of the party, none of them a single point.
    private static func targets(from spot: RoamSpot, _ inputs: RoamInputs) -> [ClosedRange<Double>] {
        let stride: ClosedRange<Double> = (spot.x - minimumStride)...(spot.x + minimumStride)
        return inputs.free(on: spot.perch, also: [stride]).filter { $0.upperBound > $0.lowerBound }
    }

    /// Anywhere in `pieces`, each as likely as its length, or a lone point
    /// when that is all there is.
    private static func pick(in pieces: [ClosedRange<Double>], using rng: inout some RandomNumberGenerator) -> Double? {
        let total: Double = pieces.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
        guard total > 0 else { return pieces.first?.lowerBound }
        var offset = Double.random(in: 0..<total, using: &rng)
        for piece in pieces {
            let length = piece.upperBound - piece.lowerBound
            if offset < length { return piece.lowerBound + offset }
            offset -= length
        }
        return pieces.last?.upperBound
    }
}

extension ClosedRange<Double> {
    /// The parts of this range outside every one of `holes`, left to right.
    func subtracting(_ holes: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        var pieces: [ClosedRange<Double>] = [self]
        for hole in holes {
            pieces = pieces.flatMap { (piece: ClosedRange<Double>) -> [ClosedRange<Double>] in
                guard piece.overlaps(hole) else { return [piece] }
                var left: [ClosedRange<Double>] = []
                if piece.lowerBound < hole.lowerBound { left.append(piece.lowerBound...hole.lowerBound) }
                if hole.upperBound < piece.upperBound { left.append(hole.upperBound...piece.upperBound) }
                return left
            }
        }
        return pieces
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

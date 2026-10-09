import Foundation

/// One stretch of a visit: what the sprite does from `from` until `until`.
struct WildLeg: Sendable, Equatable {
    let track: SpriteTrack
    let from: Date
    let until: Date
}

/// A wild creature's whole visit, planned when it arrives: it drops in,
/// rests and strolls for `EncounterRules.visitLength`, then wanders to the
/// end of its span and hops out. Every leg gives its spot at any instant,
/// so nothing ticks while it walks.
struct WildVisit: Sendable, Equatable {
    static let clearance: Double = 2 * Double(NotchGeometry.peekHeight)
    static let rest: ClosedRange<TimeInterval> = 2...5
    /// How long the catch sparkle and shrink take before it is gone.
    static let catchLength: TimeInterval = 0.6

    let perch: Perch
    /// Never empty, in time order, each leg starting where the last ended.
    let legs: [WildLeg]

    var start: Date { legs[0].from }
    var end: Date { legs[legs.count - 1].until }

    /// The leg under way at `now`, or nil before the visit and after it.
    func leg(at now: Date) -> WildLeg? {
        legs.first { now >= $0.from && now < $0.until }
    }

    /// Where its centre is along the perch at `now`, or nil when it is not there.
    func x(at now: Date) -> Double? {
        leg(at: now).map { Self.x(of: $0.track, at: now) }
    }

    /// The farthest it goes from the perch's middle, so its window can hold all of it.
    var farthest: Double {
        legs.map { (leg: WildLeg) -> Double in
            if case .walk(let walk) = leg.track { return max(abs(walk.from), abs(walk.to)) }
            return abs(Self.x(of: leg.track, at: leg.from))
        }.max() ?? 0
    }

    /// The same visit cut short at `now` by a catch where it stands.
    func caught(at now: Date) -> WildVisit? {
        guard let x = x(at: now) else { return nil }
        let kept: [WildLeg] = legs.compactMap { (leg: WildLeg) -> WildLeg? in
            guard leg.from < now else { return nil }
            return WildLeg(track: leg.track, from: leg.from, until: min(leg.until, now))
        }
        return WildVisit(perch: perch, legs: kept + [WildLeg(track: .caught(x, start: now), from: now, until: now + Self.catchLength)])
    }

    static func x(of track: SpriteTrack, at now: Date) -> Double {
        switch track {
        case .still(let x), .leave(let x, _), .arrive(let x, _), .caught(let x, _): x
        case .walk(let walk): walk.x(at: now)
        }
    }

    /// The widest stretch of `range` at least `clearance` from every point
    /// in `avoiding`, or nil when none leaves room for a stride.
    static func span(in range: ClosedRange<Double>, avoiding points: [Double], clearance: Double = clearance) -> ClosedRange<Double>? {
        var pieces: [ClosedRange<Double>] = [range]
        for point in points {
            let hole = (point - clearance)...(point + clearance)
            pieces = pieces.flatMap { (piece: ClosedRange<Double>) -> [ClosedRange<Double>] in
                guard piece.overlaps(hole) else { return [piece] }
                var left: [ClosedRange<Double>] = []
                if piece.lowerBound < hole.lowerBound { left.append(piece.lowerBound...hole.lowerBound) }
                if hole.upperBound < piece.upperBound { left.append(hole.upperBound...piece.upperBound) }
                return left
            }
        }
        let widest = pieces.max { ($0.upperBound - $0.lowerBound) < ($1.upperBound - $1.lowerBound) }
        guard let widest, widest.upperBound - widest.lowerBound >= RoamRules.minimumStride else { return nil }
        return widest
    }

    static func plan(on perch: Perch, in span: ClosedRange<Double>, start: Date, using rng: inout some RandomNumberGenerator) -> WildVisit {
        var legs: [WildLeg] = []
        var x = Double.random(in: span, using: &rng)
        var now = start + RoamRules.transferHalf
        legs.append(WildLeg(track: .arrive(x, start: start), from: start, until: now))
        let leaveBy = start + EncounterRules.visitLength
        func walk(to target: Double) {
            let stride = RoamWalk(on: perch, from: x, to: target, start: now, speed: RoamRules.walkSpeed)
            legs.append(WildLeg(track: .walk(stride), from: now, until: stride.end))
            now = stride.end
            x = target
        }
        while now < leaveBy {
            let rest = TimeInterval.random(in: Self.rest, using: &rng)
            legs.append(WildLeg(track: .still(x), from: now, until: now + rest))
            now += rest
            guard now < leaveBy, let target = target(from: x, in: span, using: &rng) else { continue }
            walk(to: target)
        }
        let exit = x - span.lowerBound < span.upperBound - x ? span.lowerBound : span.upperBound
        if exit != x { walk(to: exit) }
        legs.append(WildLeg(track: .leave(x, start: now), from: now, until: now + RoamRules.transferHalf))
        return WildVisit(perch: perch, legs: legs)
    }

    /// Anywhere in `span` at least a stride away, or nil when it is too narrow.
    private static func target(from x: Double, in span: ClosedRange<Double>, using rng: inout some RandomNumberGenerator) -> Double? {
        let left = max(0, x - RoamRules.minimumStride - span.lowerBound)
        let right = max(0, span.upperBound - x - RoamRules.minimumStride)
        guard left + right > 0 else { return nil }
        let pick = Double.random(in: 0..<(left + right), using: &rng)
        return pick < left ? span.lowerBound + pick : x + RoamRules.minimumStride + pick - left
    }
}

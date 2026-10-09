import Foundation

/// How high above its box's bottom the sprite stands over time, as keys
/// joined by straight lines. A rise or drop is one more pair of keys, so it
/// plays on the render server beside a walk without restarting it.
struct GroundPath: Equatable {
    struct Key: Equatable {
        var at: Date
        var height: Double
    }

    /// Never empty, in time order.
    let keys: [Key]

    /// How long a rise onto the Dock or a drop off it takes, close to the
    /// Dock's own slide so the creature keeps pace with it.
    static let climb: TimeInterval = 0.25

    /// Where the sprite stands once every key has played.
    var final: Double { keys[keys.count - 1].height }

    func height(at now: Date) -> Double {
        guard now > keys[0].at else { return keys[0].height }
        for (a, b) in zip(keys, keys.dropFirst()) where now < b.at {
            return a.height + (b.height - a.height) * now.timeIntervalSince(a.at) / b.at.timeIntervalSince(a.at)
        }
        return final
    }

    /// From `height` at `now`, a climb to the ground under where `track` has
    /// the creature now, then a climb at each edge of `step` a walk crosses,
    /// centred on the crossing. Nil `height` starts on that ground.
    static func plan(_ track: SpriteTrack, on step: GroundStep?, from height: Double?, at now: Date) -> GroundPath {
        let ground = { (x: Double) in step?.height(at: x) ?? 0 }
        let x: Double
        switch track {
        case .still(let at), .leave(let at, _), .arrive(let at, _), .caught(let at, _): x = at
        case .walk(let walk): x = walk.x(at: now)
        }
        var keys = [Key(at: now, height: height ?? ground(x))]
        func climb(to target: Double, startingAt time: Date) {
            let last = keys[keys.count - 1]
            guard target != last.height else { return }
            let start = max(time, last.at)
            if start > last.at { keys.append(Key(at: start, height: last.height)) }
            keys.append(Key(at: start + Self.climb, height: target))
        }
        climb(to: ground(x), startingAt: now)
        if case .walk(let walk) = track, let step, walk.from != walk.to {
            let ahead = walk.direction == .right ? 0.5 : -0.5
            let crossings = [step.span.lowerBound, step.span.upperBound]
                .map { edge in (edge: edge, at: walk.start + (edge - walk.from) / (walk.to - walk.from) * walk.duration) }
                .filter { $0.at > now && $0.at < walk.end }
                .sorted { $0.at < $1.at }
            for crossing in crossings {
                climb(to: ground(crossing.edge + ahead), startingAt: crossing.at - Self.climb / 2)
            }
        }
        return GroundPath(keys: keys)
    }
}

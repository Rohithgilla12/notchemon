import AppKit
import SwiftUI

/// Where the sprite stands along its perch, in points from its box's centre.
enum SpriteTrack: Sendable, Equatable {
    case still(Double)
    case walk(RoamWalk)
    /// Hops up and fades out at x, from `start`.
    case leave(Double, start: Date)
    /// Drops in and fades in at x, from `start`.
    case arrive(Double, start: Date)
    /// Caught at x: sparkles, shrinks, and is gone, from `start`.
    case caught(Double, start: Date)
}

/// What the sprite should show. One-shot effects are counters: the view
/// plays the effect when a counter moves.
struct SpritePose: Equatable {
    var show: SpriteShow?
    var tucked = false
    var flashToken = 0
    var fidgets = true
    var fit = SpriteFit.peek
    var idleStyle = IdleStyle.calm
    var track = SpriteTrack.still(0)
    /// A shown auto-hiding Dock the creature climbs onto over its span.
    var ground: GroundStep?

    static func == (lhs: SpritePose, rhs: SpritePose) -> Bool {
        lhs.show?.loop.frames.first === rhs.show?.loop.frames.first
            && lhs.show?.loopState == rhs.show?.loopState && lhs.show?.playback == rhs.show?.playback && lhs.show?.facing == rhs.show?.facing
            && lhs.show?.bounds == rhs.show?.bounds && lhs.fit == rhs.fit && lhs.idleStyle == rhs.idleStyle
            && lhs.show?.oneShot?.serial == rhs.show?.oneShot?.serial
            && lhs.tucked == rhs.tucked && lhs.flashToken == rhs.flashToken && lhs.fidgets == rhs.fidgets
            && lhs.track == rhs.track && lhs.ground == rhs.ground
    }
}

extension SpritePose {
    /// The pose on `perch`'s window, or nil when the creature is not there.
    /// The open panel shows it in its own slot wherever it was wandering.
    /// Closed, it walks or rests along whichever perch it is on and hops
    /// between them. Asleep, it sleeps where it stopped and tucks up behind
    /// the notch only if that is home. On a shown auto-hiding Dock it stands
    /// on the Dock over `ground`'s span and below it elsewhere.
    init?(_ snapshot: CompanionSnapshot, roam: RoamPhase, on perch: Perch, expanded: Bool, ground: GroundStep? = nil) {
        let track: SpriteTrack
        if expanded {
            guard perch == .topEdge else { return nil }
            track = .still(0)
        } else {
            guard let found = Self.track(of: roam, on: perch) else { return nil }
            track = found
        }
        let tucked = snapshot.behaviour == .sleeping && !expanded && roam == .home
        self.init(
            Self.walking(snapshot.sprite, along: track, asleep: snapshot.behaviour == .sleeping),
            track: track, tucked: tucked, flashToken: snapshot.evolutionCount, preferences: snapshot.preferences,
            fit: expanded ? .contain : .peek, ground: ground
        )
    }

    /// A follower's pose on `perch`'s window, in its own frames: asleep with
    /// the party, else watching the cursor from its own spot. It is out of
    /// sight while at home, where the leader stands, and hops out from there.
    init?(follower sprites: SpriteSet, look: FollowerLook, _ snapshot: CompanionSnapshot, roam: RoamPhase, on perch: Perch, ground: GroundStep? = nil) {
        guard let track = Self.followerTrack(of: roam, on: perch) else { return nil }
        let asleep = snapshot.behaviour == .sleeping
        let behaviour: Behaviour = asleep ? .sleeping : look.facing.map { .watching(facing: $0) } ?? .idle
        var show = sprites.show(for: behaviour, style: snapshot.preferences.idleStyle)
        if look.hops > 0, let loop = show?.loop {
            let hop = sprites.anims[.hop]?[behaviour.facing] ?? loop
            show?.oneShot = OneShot(state: .hop, frames: hop, serial: look.hops)
        }
        self.init(
            Self.walking(show, along: track, asleep: asleep),
            track: track, tucked: false, flashToken: 0, preferences: snapshot.preferences, fit: .peek, ground: ground
        )
    }

    private init(_ show: SpriteShow?, track: SpriteTrack, tucked: Bool, flashToken: Int, preferences: Preferences, fit: SpriteFit, ground: GroundStep?) {
        let still = if case .still = track { true } else { false }
        self.init(
            show: show,
            tucked: tucked,
            flashToken: flashToken,
            fidgets: preferences.fidgets && !tucked && still,
            fit: fit,
            idleStyle: preferences.idleStyle,
            track: track,
            ground: ground
        )
    }

    /// Plays the walk cycle toward the way a walk heads, unless asleep.
    private static func walking(_ show: SpriteShow?, along track: SpriteTrack, asleep: Bool) -> SpriteShow? {
        guard case .walk(let walk) = track, !asleep, var show, let cycle = show.walk else { return show }
        show.loop = cycle.frames(toward: walk.direction)
        show.loopState = .walking
        show.playback = .cycle
        show.facing = walk.direction
        return show
    }

    /// A wild creature's pose: it walks with its own walk cycle and never fidgets.
    static func wild(_ show: SpriteShow, track: SpriteTrack, idleStyle: IdleStyle, ground: GroundStep? = nil) -> SpritePose {
        var show = show
        if case .walk(let walk) = track, let cycle = show.walk {
            show.loop = cycle.frames(toward: walk.direction)
            show.loopState = .walking
            show.playback = .cycle
            show.facing = walk.direction
        }
        return SpritePose(show: show, fidgets: false, fit: .peek, idleStyle: idleStyle, track: track, ground: ground)
    }

    /// Like the leader's, less any moment at home: a follower there is out
    /// of sight, so hopping out of home it is seen only arriving, and
    /// dropping into home only leaving.
    private static func followerTrack(of roam: RoamPhase, on perch: Perch) -> SpriteTrack? {
        switch roam {
        case .home:
            return nil
        case .resting(let spot, _) where spot == .home, .stopped(let spot) where spot == .home:
            return nil
        case .transferring(let from, let to, let start) where from == .home:
            return to.perch == perch && to != .home ? .arrive(to.x, start: start + RoamRules.transferHalf) : nil
        case .transferring(let from, let to, let start) where to == .home:
            return from.perch == perch ? .leave(from.x, start: start) : nil
        case .resting, .stopped, .walking, .returning, .transferring:
            return track(of: roam, on: perch)
        }
    }

    private static func track(of roam: RoamPhase, on perch: Perch) -> SpriteTrack? {
        switch roam {
        case .home:
            perch == .topEdge ? .still(0) : nil
        case .resting(let spot, _), .stopped(let spot):
            spot.perch == perch ? .still(spot.x) : nil
        case .walking(let walk), .returning(let walk):
            walk.perch == perch ? .walk(walk) : nil
        case .transferring(let from, let to, let start):
            if from.perch == perch {
                .leave(from.x, start: start)
            } else if to.perch == perch {
                .arrive(to.x, start: start + RoamRules.transferHalf)
            } else {
                nil
            }
        }
    }
}

struct SpriteView: NSViewRepresentable {
    var pose: SpritePose

    func makeNSView(context: Context) -> SpriteHostView {
        SpriteHostView(pose: pose)
    }

    func updateNSView(_ view: SpriteHostView, context: Context) {
        view.apply(pose)
    }
}

final class SpriteHostView: NSView {
    private let sprite = SpriteLayer()
    private var pose: SpritePose
    private var fidgetTask: Task<Void, Never>?
    /// The sprite's x offset from the box's centre once any walk ends.
    private var offset: CGFloat = 0
    /// How high the sprite stands above the box's bottom over time.
    private var groundPath: GroundPath?

    init(pose: SpritePose) {
        self.pose = pose
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(sprite)
        apply(pose, initial: true)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.bounds = CGRect(origin: .zero, size: bounds.size)
        sprite.position = restingPosition
        CATransaction.commit()
    }

    private var restingPosition: CGPoint {
        CGPoint(x: bounds.midX + offset, y: bounds.midY + (groundPath?.final ?? 0))
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        sprite.contentsScale = window?.backingScaleFactor ?? 2
        sprite.backingScale = sprite.contentsScale
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            fidgetTask?.cancel()
            fidgetTask = nil
        } else {
            scheduleFidgets()
        }
    }

    // Purely decorative; clicks go to whatever SwiftUI put underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(_ next: SpritePose, initial: Bool = false) {
        let previous = pose
        pose = next
        sprite.setTucked(next.tucked)
        sprite.fit = next.fit
        sprite.idleStyle = next.idleStyle
        sprite.show(next.show, playOneShot: !initial)
        if initial || next.track != previous.track { follow(next.track) }
        if initial || next.track != previous.track || next.ground != previous.ground { settle(on: next.ground) }
        guard !initial else { return }
        if next.flashToken != previous.flashToken { sprite.flash() }
        if next.fidgets != previous.fidgets { scheduleFidgets() }
    }

    /// A walk is one linear animation the render server plays, timed from
    /// the walk's own start so a view made mid-walk joins it in step. It is
    /// additive, relative to where the walk ends, so the box moving under it
    /// does not throw it off. A hop between perches is timed the same way.
    private func follow(_ track: SpriteTrack) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.removeAnimation(forKey: "walk")
        sprite.removeAnimation(forKey: "transfer")
        sprite.opacity = 1
        switch track {
        case .still(let x):
            offset = x
        case .walk(let walk):
            offset = walk.to
            let stride = CABasicAnimation(keyPath: "position.x")
            stride.fromValue = walk.from - walk.to
            stride.toValue = 0
            stride.isAdditive = true
            stride.duration = walk.duration
            stride.beginTime = CACurrentMediaTime() + walk.start.timeIntervalSinceNow
            stride.timingFunction = CAMediaTimingFunction(name: .linear)
            stride.fillMode = .backwards
            sprite.add(stride, forKey: "walk")
        case .leave(let x, let start):
            offset = x
            sprite.opacity = 0
            sprite.add(Self.hop(arriving: false, at: start), forKey: "transfer")
        case .arrive(let x, let start):
            offset = x
            sprite.add(Self.hop(arriving: true, at: start), forKey: "transfer")
        case .caught(let x, let start):
            offset = x
            sprite.opacity = 0
            sprite.add(Self.vanish(at: start), forKey: "transfer")
            sprite.flash()
        }
        sprite.position = restingPosition
        CATransaction.commit()
    }

    /// Rises onto or drops off a shown Dock from wherever the sprite stands
    /// now, then climbs at each edge of it the walk crosses. A separate
    /// additive animation, so the walk's and a hop's carry on untouched.
    private func settle(on step: GroundStep?) {
        let now = Date()
        let path = GroundPath.plan(pose.track, on: step, from: groundPath?.height(at: now), at: now)
        groundPath = path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.removeAnimation(forKey: "ground")
        if let first = path.keys.first, let last = path.keys.last, last.at > first.at {
            let span = last.at.timeIntervalSince(first.at)
            let climb = CAKeyframeAnimation(keyPath: "position.y")
            climb.values = path.keys.map { $0.height - path.final }
            climb.keyTimes = path.keys.map { NSNumber(value: $0.at.timeIntervalSince(first.at) / span) }
            climb.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: path.keys.count - 1)
            climb.isAdditive = true
            climb.duration = span
            climb.beginTime = CACurrentMediaTime() + first.at.timeIntervalSinceNow
            climb.fillMode = .backwards
            sprite.add(climb, forKey: "ground")
        }
        sprite.position = restingPosition
        CATransaction.commit()
    }

    static let hopRise: CGFloat = 10

    /// Filled backwards, so an arrival stays hidden until it begins and a
    /// leaving creature stays in view until it goes.
    private static func hop(arriving: Bool, at start: Date) -> CAAnimationGroup {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = arriving ? 0 : 1
        fade.toValue = arriving ? 1 : 0
        let rise = CABasicAnimation(keyPath: "position.y")
        rise.fromValue = arriving ? hopRise : 0
        rise.toValue = arriving ? 0 : hopRise
        rise.isAdditive = true
        let hop = CAAnimationGroup()
        hop.animations = [fade, rise]
        hop.duration = RoamRules.transferHalf
        hop.beginTime = CACurrentMediaTime() + start.timeIntervalSinceNow
        hop.timingFunction = CAMediaTimingFunction(name: arriving ? .easeOut : .easeIn)
        hop.fillMode = .backwards
        return hop
    }

    /// Shrinks to a point and fades under the evolution bloom, which reads
    /// as a sparkle. Filled backwards, so it stays in view until it begins.
    private static func vanish(at start: Date) -> CAAnimationGroup {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1
        shrink.toValue = 0.1
        let group = CAAnimationGroup()
        group.animations = [fade, shrink]
        group.duration = WildVisit.catchLength
        group.beginTime = CACurrentMediaTime() + start.timeIntervalSinceNow
        group.timingFunction = CAMediaTimingFunction(name: .easeIn)
        group.fillMode = .backwards
        return group
    }

    /// One wake-up every 5 to 15 s; nothing runs in between.
    private func scheduleFidgets() {
        fidgetTask?.cancel()
        guard pose.fidgets, window != nil else { return }
        fidgetTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 5...15)))
                guard !Task.isCancelled else { return }
                self?.sprite.fidget()
            }
        }
    }
}

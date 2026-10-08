import AppKit
import SwiftUI

/// Where the sprite stands along the strip, in points from its box's centre.
enum SpriteTrack: Equatable {
    case still(Double)
    case walk(RoamWalk)
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

    static func == (lhs: SpritePose, rhs: SpritePose) -> Bool {
        lhs.show?.loop.frames.first === rhs.show?.loop.frames.first
            && lhs.show?.loopState == rhs.show?.loopState && lhs.show?.playback == rhs.show?.playback && lhs.show?.facing == rhs.show?.facing
            && lhs.show?.bounds == rhs.show?.bounds && lhs.fit == rhs.fit && lhs.idleStyle == rhs.idleStyle
            && lhs.show?.oneShot?.serial == rhs.show?.oneShot?.serial
            && lhs.tucked == rhs.tucked && lhs.flashToken == rhs.flashToken && lhs.fidgets == rhs.fidgets
            && lhs.track == rhs.track
    }
}

extension SpritePose {
    /// The open panel shows the creature in its own slot wherever it was
    /// wandering. Closed, it walks or rests along the strip. Asleep, it
    /// sleeps where it stopped and tucks up behind the notch only if that is
    /// home.
    init(_ snapshot: CompanionSnapshot, roam: RoamPhase, expanded: Bool) {
        let walk = expanded ? nil : roam.walk
        var show = snapshot.sprite
        if let walk, snapshot.behaviour != .sleeping, let cycle = show?.walk {
            show?.loop = cycle.frames(toward: walk.direction)
            show?.loopState = .walking
            show?.playback = .cycle
            show?.facing = walk.direction
        }
        let tucked = snapshot.behaviour == .sleeping && !expanded && roam == .home
        let track: SpriteTrack = switch roam {
        case _ where expanded, .home: .still(0)
        case .resting(let x, _), .asleep(let x): .still(x)
        case .walking(let walk), .returning(let walk): .walk(walk)
        }
        self.init(
            show: show,
            tucked: tucked,
            flashToken: snapshot.evolutionCount,
            fidgets: snapshot.preferences.fidgets && !tucked && walk == nil,
            fit: expanded ? .contain : .peek,
            idleStyle: snapshot.preferences.idleStyle,
            track: track
        )
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
        sprite.position = CGPoint(x: bounds.midX + offset, y: bounds.midY)
        CATransaction.commit()
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
        guard !initial else { return }
        if next.flashToken != previous.flashToken { sprite.flash() }
        if next.fidgets != previous.fidgets { scheduleFidgets() }
    }

    /// A walk is one linear animation the render server plays, timed from
    /// the walk's own start so a view made mid-walk joins it in step. It is
    /// additive, relative to where the walk ends, so the box moving under it
    /// does not throw it off.
    private func follow(_ track: SpriteTrack) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.removeAnimation(forKey: "walk")
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
        }
        sprite.position = CGPoint(x: bounds.midX + offset, y: bounds.midY)
        CATransaction.commit()
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

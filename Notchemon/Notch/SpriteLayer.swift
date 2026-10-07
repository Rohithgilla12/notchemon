import QuartzCore

/// Renders the creature. Every motion is a Core Animation animation, so frame
/// stepping, bobbing and hops run in the render server and the app process
/// stays idle between state changes; no display link is needed.
final class SpriteLayer: CALayer {
    private let body = CALayer()
    private let image = CALayer()
    private let flashGlow = CAGradientLayer()
    private var loop: SpriteFrames?
    private var loopStart: CFTimeInterval = 0
    private var reference: SpriteFrames?
    private var footprint = Footprint(top: -1, bottom: 0)
    private var oneShot: (animation: CAKeyframeAnimation, ends: CFTimeInterval)?
    private var playedOneShot: Int?
    private var tucked = false
    private var mirrored = false

    var backingScale: CGFloat = 2 {
        didSet { if backingScale != oldValue { setNeedsLayout() } }
    }

    override init() {
        super.init()
        masksToBounds = false
        addSublayer(body)
        body.addSublayer(image)
        // Contents keep their own size around the layer's centre, so frames
        // of any size share the centre the sheets are drawn around, and tall
        // ones (a hop with its arc drawn in) rise up behind the notch.
        image.contentsGravity = .center
        flashGlow.type = .radial
        flashGlow.colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)]
        flashGlow.startPoint = CGPoint(x: 0.5, y: 0.5)
        flashGlow.endPoint = CGPoint(x: 1, y: 1)
        flashGlow.opacity = 0
        addSublayer(flashGlow)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body.bounds = bounds
        body.position = CGPoint(x: bounds.midX, y: bounds.midY + (tucked ? tuckDistance : 0))
        image.bounds = body.bounds
        placeImage()
        flashGlow.frame = bounds.insetBy(dx: -bounds.width * 0.4, dy: -bounds.height * 0.4)
        CATransaction.commit()
    }

    private var tuckDistance: CGFloat { bounds.height + 6 }

    /// One scale and one anchor per species, both from its idle frames, so
    /// switching anims never resizes or shifts the creature. The idle feet
    /// rest on the bottom of the box and the idle body fits inside it.
    private func placeImage() {
        let points = SpriteRendering.pointsPerPixel(
            visibleHeight: footprint.height,
            boxHeight: bounds.height,
            backingScale: backingScale,
            pixelated: loop?.pixelated ?? true
        )
        image.contentsScale = 1 / points
        image.position = CGPoint(x: bounds.midX, y: bounds.minY + CGFloat(footprint.bottom) * points)
    }

    /// `playOneShot` is false for the first pose a view sees, so a one-shot
    /// that finished before the view existed is not replayed.
    func show(_ show: SpriteShow?, playOneShot: Bool) {
        guard let show else {
            loop = nil
            image.removeAllAnimations()
            image.contents = nil
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let newSpecies = show.reference.frames.first !== reference?.frames.first
        let replace = newSpecies || show.loop.pixelated != loop?.pixelated
        if newSpecies {
            reference = show.reference
            footprint = SpriteRendering.footprint(of: show.reference.frames) ?? footprint
        }
        setLoop(show.loop)
        if replace { placeImage() }
        setMirrored(!show.loop.directional && show.facing.horizontal > 0)
        CATransaction.commit()
        body.setValue(CGFloat(show.facing.horizontal) * 3, forKeyPath: "transform.translation.x")

        if let next = show.oneShot, next.serial != playedOneShot {
            playedOneShot = next.serial
            if playOneShot { play(next) }
        }
    }

    /// A new facing of the same anim keeps the loop's phase, so turning to
    /// follow the cursor never restarts the animation.
    private func setLoop(_ frames: SpriteFrames) {
        guard loop?.frames.first !== frames.frames.first else { return }
        let samePhase = loop?.durations == frames.durations && image.animation(forKey: "loop") != nil
        loop = frames
        let filter: CALayerContentsFilter = frames.pixelated ? .nearest : .trilinear
        image.magnificationFilter = filter
        image.minificationFilter = filter
        image.contents = frames.frames[0]
        image.removeAnimation(forKey: "loop")
        image.removeAnimation(forKey: "bob")
        if frames.frames.count > 1 {
            if !samePhase { loopStart = CACurrentMediaTime() }
            let animation = Self.keyframes(frames)
            animation.beginTime = loopStart
            animation.repeatCount = .infinity
            image.add(animation, forKey: "loop")
            restoreOneShot()
        } else {
            let bob = CAKeyframeAnimation(keyPath: "transform.translation.y")
            bob.values = [0, 2]
            bob.calculationMode = .discrete
            bob.duration = 1.0
            bob.repeatCount = .infinity
            bob.isAdditive = true
            image.add(bob, forKey: "bob")
        }
    }

    /// Core Animation applies the most recently added animation on a key path
    /// last, so a one-shot added after the loop covers it, and the loop shows
    /// through again once the one-shot is removed on completion.
    private func play(_ oneShot: OneShot) {
        guard oneShot.frames.loops else {
            let animation = Self.keyframes(oneShot.frames)
            animation.beginTime = CACurrentMediaTime()
            image.add(animation, forKey: "oneShot")
            self.oneShot = (animation, animation.beginTime + animation.duration)
            return
        }
        switch oneShot.state {
        case .hop: hop(height: 8)
        case .wake: hop(height: 6)
        case .celebrating: celebrate()
        case .idle, .sleeping: break
        }
    }

    private func restoreOneShot() {
        guard let oneShot, oneShot.ends > CACurrentMediaTime() else { return }
        image.removeAnimation(forKey: "oneShot")
        image.add(oneShot.animation, forKey: "oneShot")
    }

    private static func keyframes(_ frames: SpriteFrames) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames.frames
        animation.keyTimes = SpriteRendering.keyTimes(for: frames.durations).map { NSNumber(value: $0) }
        animation.calculationMode = .discrete
        animation.duration = frames.totalDuration
        return animation
    }

    /// Frames that do not face the requested way face left; mirroring turns
    /// them right.
    private func setMirrored(_ mirrored: Bool) {
        guard mirrored != self.mirrored else { return }
        self.mirrored = mirrored
        image.setAffineTransform(mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
    }

    /// Asleep, the creature ducks up behind the notch; any input pops it out.
    func setTucked(_ tucked: Bool) {
        guard tucked != self.tucked else { return }
        self.tucked = tucked
        CATransaction.begin()
        CATransaction.setAnimationDuration(tucked ? 0.9 : 0.35)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: tucked ? .easeInEaseOut : .easeOut))
        body.position = CGPoint(x: bounds.midX, y: bounds.midY + (tucked ? tuckDistance : 0))
        CATransaction.commit()
    }

    private func hop(height: CGFloat) {
        guard !tucked else { return }
        let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
        hop.values = [0, height, 0, height * 0.3, 0]
        hop.keyTimes = [0, 0.35, 0.7, 0.85, 1]
        hop.duration = 0.45
        hop.isAdditive = true
        image.add(hop, forKey: "hop")
    }

    private func celebrate() {
        let jumps = CAKeyframeAnimation(keyPath: "transform.translation.y")
        jumps.values = [0, 10, 0, 10, 0, 10, 0]
        jumps.duration = 2
        jumps.isAdditive = true
        image.add(jumps, forKey: "celebrate")
    }

    /// The idle blink-or-shift: a quick squash or a small sidestep.
    func fidget() {
        guard !tucked else { return }
        let animation: CAKeyframeAnimation
        if Bool.random() {
            animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
            animation.values = [1, 0.9, 1]
        } else {
            animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            let step = CGFloat.random(in: 2...4) * (Bool.random() ? 1 : -1)
            animation.values = [0, step, step, 0]
            animation.isAdditive = true
        }
        animation.duration = 0.5
        image.add(animation, forKey: "fidget")
    }

    /// Evolution: a white bloom that peaks as the new sprite swaps in.
    func flash() {
        let bloom = CAKeyframeAnimation(keyPath: "opacity")
        bloom.values = [0, 1, 1, 0]
        bloom.keyTimes = [0, 0.3, 0.55, 1]
        bloom.duration = 1.2
        flashGlow.add(bloom, forKey: "flash")
    }
}

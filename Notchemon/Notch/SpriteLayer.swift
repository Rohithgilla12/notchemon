import QuartzCore

/// Renders the creature. Every motion is a Core Animation animation, so frame
/// stepping, bobbing and hops run in the render server and the app process
/// stays idle between state changes; no display link is needed.
final class SpriteLayer: CALayer {
    private let body = CALayer()
    private let image = CALayer()
    private let flashGlow = CAGradientLayer()
    private var shownFrames: ObjectIdentifier?
    private var tucked = false
    private var facingRight = false

    override init() {
        super.init()
        masksToBounds = false
        addSublayer(body)
        body.addSublayer(image)
        image.contentsGravity = .resizeAspect
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
        image.frame = body.bounds
        flashGlow.frame = bounds.insetBy(dx: -bounds.width * 0.4, dy: -bounds.height * 0.4)
        CATransaction.commit()
    }

    private var tuckDistance: CGFloat { bounds.height + 6 }

    func show(_ frames: SpriteFrames?) {
        let identity = frames?.frames.first.map(ObjectIdentifier.init)
        guard identity != shownFrames else { return }
        shownFrames = identity
        image.removeAnimation(forKey: "frames")
        image.removeAnimation(forKey: "bob")
        guard let frames, let first = frames.frames.first else {
            image.contents = nil
            return
        }
        let filter: CALayerContentsFilter = frames.pixelated ? .nearest : .trilinear
        image.magnificationFilter = filter
        image.contents = first
        if frames.isAnimated {
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = frames.frames
            animation.calculationMode = .discrete
            animation.duration = frames.frameDuration * Double(frames.frames.count)
            animation.repeatCount = .infinity
            image.add(animation, forKey: "frames")
        } else {
            let bob = CAKeyframeAnimation(keyPath: "transform.translation.y")
            bob.values = [0, 2]
            bob.calculationMode = .discrete
            bob.duration = 1.0
            bob.repeatCount = .infinity
            image.add(bob, forKey: "bob")
        }
    }

    /// Sprites face left; a cursor to the right flips them, and the body
    /// leans a few points towards the cursor.
    func gaze(_ gaze: Double?) {
        let right = (gaze ?? 0) > 0.15
        if right != facingRight {
            facingRight = right
            image.setAffineTransform(right ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        }
        let lean = CGFloat(gaze ?? 0) * 3
        body.setValue(lean, forKeyPath: "transform.translation.x")
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
        if !tucked { hop(height: 6) }
    }

    func hop(height: CGFloat = 8) {
        guard !tucked else { return }
        let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
        hop.values = [0, height, 0, height * 0.3, 0]
        hop.keyTimes = [0, 0.35, 0.7, 0.85, 1]
        hop.duration = 0.45
        hop.isAdditive = true
        image.add(hop, forKey: "hop")
    }

    func celebrate() {
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

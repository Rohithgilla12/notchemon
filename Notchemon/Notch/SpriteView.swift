import AppKit
import SwiftUI

/// What the sprite should show. One-shot effects are counters: the view
/// plays the effect when a counter moves.
struct SpritePose: Equatable {
    var show: SpriteShow?
    var tucked = false
    var flashToken = 0
    var fidgets = true
    var fit = SpriteFit.peek
    var idleStyle = IdleStyle.calm

    static func == (lhs: SpritePose, rhs: SpritePose) -> Bool {
        lhs.show?.loop.frames.first === rhs.show?.loop.frames.first
            && lhs.show?.loopState == rhs.show?.loopState && lhs.show?.playback == rhs.show?.playback && lhs.show?.facing == rhs.show?.facing
            && lhs.show?.bounds == rhs.show?.bounds && lhs.fit == rhs.fit && lhs.idleStyle == rhs.idleStyle
            && lhs.show?.oneShot?.serial == rhs.show?.oneShot?.serial
            && lhs.tucked == rhs.tucked && lhs.flashToken == rhs.flashToken && lhs.fidgets == rhs.fidgets
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
        sprite.frame = bounds
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
        guard !initial else { return }
        if next.flashToken != previous.flashToken { sprite.flash() }
        if next.fidgets != previous.fidgets { scheduleFidgets() }
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

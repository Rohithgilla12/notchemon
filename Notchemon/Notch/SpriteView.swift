import AppKit
import SwiftUI

/// What the sprite should show. One-shot effects are counters: the view
/// plays the effect when a counter moves.
struct SpritePose: Equatable {
    var frames: SpriteFrames?
    var gaze: Double?
    var tucked = false
    var celebrating = false
    var hopToken = 0
    var flashToken = 0
    var fidgets = true

    static func == (lhs: SpritePose, rhs: SpritePose) -> Bool {
        lhs.frames?.frames.first === rhs.frames?.frames.first
            && lhs.gaze == rhs.gaze && lhs.tucked == rhs.tucked && lhs.celebrating == rhs.celebrating
            && lhs.hopToken == rhs.hopToken && lhs.flashToken == rhs.flashToken && lhs.fidgets == rhs.fidgets
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
        sprite.show(next.frames)
        sprite.gaze(next.gaze)
        sprite.setTucked(next.tucked)
        guard !initial else { return }
        if next.hopToken != previous.hopToken { sprite.hop() }
        if next.flashToken != previous.flashToken { sprite.flash() }
        if next.celebrating, !previous.celebrating { sprite.celebrate() }
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

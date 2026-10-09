import AppKit
import SwiftUI

/// Shows the creature on the Dock. It takes the mouse only over a visiting
/// wild creature, so the Dock under it stays usable.
@MainActor
final class DockWindowController {
    private let panel = DockPanel()
    private var placement = DockWindowPlacement()

    init<Content: View>(content: Content) {
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    /// On screen only while the creature is on the Dock or hopping to or from it.
    func show(on shelf: DockShelf?, creatureThere: Bool) {
        guard let frame = placement.frame(for: shelf, creatureThere: creatureThere, current: panel.frame) else {
            panel.orderOut(nil)
            return
        }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Only over a visiting creature, which a click catches.
    func setTakesClicks(_ takes: Bool) {
        if panel.ignoresMouseEvents == takes { panel.ignoresMouseEvents = !takes }
    }
}

/// Where the Dock window goes. A Dock that goes while the creature is on it
/// keeps its window until the creature has hopped off, so the hop is seen.
struct DockWindowPlacement {
    private var last: DockShelf?

    /// The window's frame, or nil when it should be hidden.
    mutating func frame(for shelf: DockShelf?, creatureThere: Bool, current: CGRect) -> CGRect? {
        guard creatureThere else {
            last = nil
            return nil
        }
        last = shelf ?? last
        return last?.panel(keeping: current)
    }
}

final class DockPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // After isFloatingPanel, which would otherwise reset the level. One
        // above the Dock, so the creature stands in front of it.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

struct DockRootView: View {
    let model: CompanionModel
    let roamer: Roamer
    let wild: WildWalker
    let dock: DockWatcher

    var body: some View {
        ZStack {
            if model.activeSpecies != nil,
               let pose = SpritePose(model.snapshot, roam: roamer.phase, on: .dock, expanded: false, ground: dock.shelf?.step) {
                SpriteView(pose: pose)
                    .frame(width: DockShelf.spriteSide, height: DockShelf.spriteSide)
            }
            if let encounter = model.snapshot.encounter, wild.visit?.perch == .dock, let track = wild.track {
                SpriteView(pose: .wild(encounter.show, track: track, idleStyle: .lively, ground: dock.shelf?.step))
                    .frame(width: DockShelf.spriteSide, height: DockShelf.spriteSide)
                    .id(encounter.serial)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

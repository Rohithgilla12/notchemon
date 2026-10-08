import AppKit
import SwiftUI

/// Owns the notch panel: which screen it sits on, its layout, and the hover
/// rules that decide when it expands and when it is hit-testable.
@MainActor
final class NotchWindowController {
    let presentation: NotchPresentation
    /// Every cursor position seen, in global screen coordinates.
    var onCursorMoved: ((CGPoint) -> Void)?

    private let panel: NotchPanel
    private var virtualNotchEnabled: Bool
    private var wander: WanderRange
    private var pokeballMode: Bool
    private var screen: ScreenMetrics?
    private var creatureExtent: CGFloat = 0
    private var observers: [NSObjectProtocol] = []
    private var monitors: [Any] = []
    private var pressPoll: Timer?
    private var dragChangeCountAtPress = 0
    private var collapseTask: Task<Void, Never>?

    static let collapseDelay: Duration = .milliseconds(500)

    init<Content: View>(presentation: NotchPresentation, virtualNotchEnabled: Bool, wander: WanderRange, pokeballMode: Bool, content: Content) {
        self.presentation = presentation
        self.virtualNotchEnabled = virtualNotchEnabled
        self.wander = wander
        self.pokeballMode = pokeballMode
        panel = NotchPanel(frame: .zero)
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.acceptsMouseMovedEvents = true
        panel.onEscape = { [weak self] in self?.collapse() }
    }

    func start() {
        relayout()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.relayout() }
            })
        }
        installMouseMonitors()
    }

    func setVirtualNotchEnabled(_ enabled: Bool) {
        guard enabled != virtualNotchEnabled else { return }
        virtualNotchEnabled = enabled
        relayout()
    }

    func setWander(_ wander: WanderRange) {
        guard wander != self.wander else { return }
        self.wander = wander
        relayout()
    }

    func setPokeballMode(_ mode: Bool) {
        guard mode != pokeballMode else { return }
        pokeballMode = mode
        handleCursor(NSEvent.mouseLocation)
    }

    func relayout() {
        guard let screen = NSScreen.notchHost else {
            self.screen = nil
            apply(layout: nil)
            return
        }
        self.screen = screen.metrics
        presentation.isFullScreen = FullScreenDetector.isFullScreen(screen)
        apply(layout: layout())
    }

    /// How far from home the creature stands or walks. It changes with every
    /// phase but moves the window only while the creature is outside its range.
    func setCreatureExtent(_ extent: CGFloat) {
        guard extent != creatureExtent else { return }
        creatureExtent = extent
        let next = layout()
        guard next != presentation.layout else { return }
        apply(layout: next)
    }

    private func layout() -> NotchLayout? {
        screen.flatMap {
            NotchGeometry.layout(
                for: $0, virtualNotchEnabled: virtualNotchEnabled, fullScreen: presentation.isFullScreen, wander: wander, covering: creatureExtent
            )
        }
    }

    func toggleFromHotkey() {
        if presentation.isExpanded {
            collapse()
        } else {
            expandPinned(focusNote: true)
        }
    }

    func expandPinned(focusNote: Bool) {
        guard presentation.layout != nil else { return }
        collapseTask?.cancel()
        setMode(.expanded(.pinned))
        if focusNote {
            panel.makeKeyAndOrderFront(nil)
            presentation.noteFocusRequested = true
        }
        // collapse() left the panel click-through; a click without a mouse
        // move first would otherwise land in the app underneath.
        handleCursor(NSEvent.mouseLocation)
    }

    func collapse() {
        collapseTask?.cancel()
        setMode(.collapsed)
        panel.ignoresMouseEvents = true
        panel.relinquishKey()
    }

    private func apply(layout: NotchLayout?) {
        presentation.layout = layout
        guard let layout else {
            panel.orderOut(nil)
            return
        }
        panel.setFrame(layout.panel, display: true)
        panel.orderFrontRegardless()
        handleCursor(NSEvent.mouseLocation)
    }

    private func setMode(_ mode: PanelMode) {
        guard mode != presentation.mode else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            presentation.mode = mode
        }
        // The sprite moved, so the creature must look at the cursor again from where it now stands.
        onCursorMoved?(NSEvent.mouseLocation)
    }

    private func installMouseMonitors() {
        let moved: NSEvent.EventTypeMask = [.mouseMoved]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moved, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.handleCursor(NSEvent.mouseLocation) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moved, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleCursor(NSEvent.mouseLocation) }
            return event
        }) {
            monitors.append(local)
        }
        if let press = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.beginPressPolling() }
        }) {
            monitors.append(press)
        }
    }

    /// A drag in progress sends no mouse-moved events, so while a button is
    /// held we poll the cursor instead. The timer only exists for the press.
    private func beginPressPolling() {
        dragChangeCountAtPress = NSPasteboard(name: .drag).changeCount
        pressPoll?.invalidate()
        pressPoll = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollPress() }
        }
    }

    private func pollPress() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            pressPoll?.invalidate()
            pressPoll = nil
            return
        }
        guard isFileDragInProgress else { return }
        handleCursor(NSEvent.mouseLocation)
    }

    private var isFileDragInProgress: Bool {
        let pasteboard = NSPasteboard(name: .drag)
        return pasteboard.changeCount != dragChangeCountAtPress && pasteboard.types?.contains(.fileURL) == true
    }

    private func handleCursor(_ point: CGPoint) {
        onCursorMoved?(point)
        guard let layout = presentation.layout else { return }
        let buttonHeld = pressPoll != nil && !isFileDragInProgress
        let decision = HoverPolicy.react(to: point, mode: presentation.mode, layout: layout, buttonHeld: buttonHeld, pokeballModeEnabled: pokeballMode)
        // Each assignment is a WindowServer round trip; mouse moves arrive at 120 Hz.
        if panel.ignoresMouseEvents == decision.hitTestable {
            panel.ignoresMouseEvents = !decision.hitTestable
        }
        setMode(decision.mode)
        switch decision.collapse {
        case .schedule:
            scheduleCollapse()
        case .cancel:
            collapseTask?.cancel()
            collapseTask = nil
        case .unchanged:
            break
        }
    }

    private func scheduleCollapse() {
        guard collapseTask == nil else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: Self.collapseDelay)
            guard !Task.isCancelled else { return }
            self?.collapseTask = nil
            self?.collapse()
        }
    }
}

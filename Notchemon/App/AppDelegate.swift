import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let debugSessionSecondsKey = "NotchemonDebugSessionSeconds"
    static let debugSleepSecondsKey = "NotchemonDebugSleepSeconds"

    let presentation = NotchPresentation()
    let roamer = Roamer()
    let dockWatcher = DockWatcher()
    let model: CompanionModel
    let notes: FloatingNotes
    private(set) var windowController: NotchWindowController?
    private var dockController: DockWindowController?
    private var hotKey: HotKey?
    private var notesHotKey: HotKey?
    private var cursorNearHome = false
    private let quitPrompt: any QuitPrompt
    private let endsSession: @MainActor () -> Bool
    private let terminate: @MainActor () -> Void
    private var quitState = QuitState.running

    private enum QuitState {
        case running
        case asking
        case approved
    }

    override convenience init() {
        let notes = FloatingNotes.shared
        self.init(
            notes: notes,
            quitPrompt: AlertQuitPrompt(notes: notes),
            endsSession: { QuitReason.endsSession(NSAppleEventManager.shared().currentAppleEvent) },
            terminate: { NSApp.terminate(nil) }
        )
    }

    init(
        notes: FloatingNotes,
        quitPrompt: any QuitPrompt,
        endsSession: @escaping @MainActor () -> Bool,
        terminate: @escaping @MainActor () -> Void
    ) {
        self.notes = notes
        self.quitPrompt = quitPrompt
        self.endsSession = endsSession
        self.terminate = terminate
        let defaults = UserDefaults.standard
        let sessionSeconds = defaults.double(forKey: Self.debugSessionSecondsKey)
        let sleepSeconds = defaults.double(forKey: Self.debugSleepSecondsKey)
        let engine = CreatureEngine(
            provider: CreatureProviderFactory.make(),
            store: .standard,
            sessionSecondsOverride: sessionSeconds > 0 ? sessionSeconds : nil,
            sleepAfter: sleepSeconds > 0 ? sleepSeconds : BehaviourRules.sleepAfter
        )
        model = CompanionModel(engine: engine)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The test bundle is hosted in the app; tests must not open panels or touch user state.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let controller = NotchWindowController(
            presentation: presentation,
            virtualNotchEnabled: model.snapshot.preferences.virtualNotchEnabled,
            wander: model.snapshot.preferences.wander,
            clickToOpen: model.snapshot.preferences.clickToOpen,
            content: NotchRootView(presentation: presentation, model: model, roamer: roamer)
        )
        windowController = controller
        dockController = DockWindowController(content: DockRootView(model: model, roamer: roamer, dock: dockWatcher))
        controller.onCursorMoved = { [weak self] point in self?.cursorMoved(to: point) }
        // Arriving, setting off, or walking up to or past a still cursor moves
        // the creature, not the cursor, so it looks again from where it is.
        // On or bound for the Dock, the Dock may have changed size since the
        // last read, so it is read again here rather than polled.
        roamer.onLookAgain = { [weak self, weak controller] in
            guard let self else { return }
            if roamer.phase.touches(.dock) { dockWatcher.refresh() }
            controller?.setCreatureExtent(roamer.phase.farthestAlongTopEdge)
            showDock()
            cursorMoved(to: NSEvent.mouseLocation)
        }
        dockWatcher.onChange = { [weak self] in
            guard let self else { return }
            showDock()
            cursorMoved(to: NSEvent.mouseLocation)
        }
        model.onSnapshot = { [weak self] in self?.refreshRoam() }
        model.onPreferencesChanged = { [weak self, weak controller] preferences in
            controller?.setVirtualNotchEnabled(preferences.virtualNotchEnabled)
            controller?.setWander(preferences.wander)
            controller?.setClickToOpen(preferences.clickToOpen)
            self?.dockWatcher.setWanted(preferences.wander.includesDock)
        }
        model.onChoosingStarter = { [weak controller] in
            controller?.expandPinned(focusNote: false)
        }
        controller.start()
        dockWatcher.start(wanted: model.snapshot.preferences.wander.includesDock)
        hotKey = HotKey.controlOptionN { [weak controller] in controller?.toggleFromHotkey() }
        notesHotKey = HotKey.controlOptionCommandN { [notes] in notes.toggle() }
        Task { await model.run() }
    }

    /// Quitting waits until every note is saved, copied elsewhere, or
    /// knowingly discarded, so a failed save never loses text silently.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch quitState {
        case .approved: return .terminateNow
        case .asking: return .terminateCancel
        case .running: break
        }
        guard case .ask(let failures) = QuitDecision.after(saving: notes.session.flush()) else { return .terminateNow }
        quitState = .asking
        if endsSession() {
            // Cancelling would abandon the logout, restart, or shutdown, and
            // macOS holds it until this returns, so the alert runs right here.
            resolveQuit(failures)
            quitState = .approved
            return .terminateNow
        }
        DispatchQueue.main.async { [self] in
            resolveQuit(failures)
            quitState = .approved
            terminate()
        }
        return .terminateCancel
    }

    private func resolveQuit(_ failures: [NoteSaveFailure]) {
        var decision = QuitDecision.ask(failures)
        while case .ask(let failures) = decision {
            decision = QuitDecision.after(
                quitPrompt.choose(for: failures),
                for: failures,
                retry: { notes.session.flush() },
                copy: quitPrompt.saveCopy(of:)
            )
        }
    }

    private func showDock() {
        dockController?.show(on: dockWatcher.shelf, creatureThere: roamer.phase.touches(.dock))
    }

    /// Offsets are measured from where the creature is now, mid-walk and on
    /// the Dock too, so it faces and hops at the cursor from its own spot. A
    /// cursor near home calls it running back to greet it.
    private func cursorMoved(to point: CGPoint) {
        dockWatcher.cursorMoved(to: point)
        guard let layout = presentation.layout, let metrics = presentation.metrics else {
            roamer.watch(nil)
            refreshRoam()
            return
        }
        let home = metrics.spriteCentre(expanded: false, roamX: 0, panelFrame: layout.expanded)
        cursorNearHome = hypot(point.x - home.x, point.y - home.y) <= BehaviourRules.watchRadius
        let perchOrigin = closedCentre(on: roamer.phase.perch, at: 0) ?? home
        roamer.watch(CursorOffset(dx: point.x - perchOrigin.x, dy: point.y - perchOrigin.y))
        refreshRoam()
        let expanded = presentation.isExpanded
        let spot = roamer.phase.spot(at: Date())
        let centre = expanded
            ? metrics.spriteCentre(expanded: true, roamX: 0, panelFrame: layout.expanded)
            : closedCentre(on: spot.perch, at: spot.x) ?? home
        model.cursorMoved(to: point, spriteCentre: centre, panelExpanded: expanded)
    }

    /// The closed creature's centre in global screen coordinates, `x` along
    /// `perch`, or nil when that perch is not on screen.
    private func closedCentre(on perch: Perch, at x: Double) -> CGPoint? {
        switch perch {
        case .topEdge:
            guard let layout = presentation.layout, let metrics = presentation.metrics else { return nil }
            return metrics.spriteCentre(expanded: false, roamX: x, panelFrame: layout.expanded)
        case .dock:
            return dockWatcher.shelf?.spriteCentre(x: x)
        }
    }

    private func refreshRoam() {
        let snapshot = model.snapshot
        let conditions = HomingConditions(
            wander: snapshot.preferences.wander,
            panelOpen: presentation.isExpanded,
            sleeping: snapshot.behaviour == .sleeping,
            focusing: snapshot.focus != nil,
            fullScreen: presentation.isFullScreen,
            cursorNearHome: cursorNearHome,
            hasCreature: model.activeSpecies != nil,
            perch: roamer.phase.perch
        )
        let reach = Double(presentation.layout?.roamReach ?? 0)
        roamer.update(range: -reach...reach, dock: dockWatcher.shelf?.range, homing: RoamRules.homing(conditions))
    }

    func confirmNewStarter() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Choose a new creature?"
        alert.informativeText = "Your current companion's level and XP will be reset. This cannot be undone."
        alert.addButton(withTitle: "Choose New Creature")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.resetForNewStarter()
    }

    /// The only place the app asks for Accessibility, and only when the user
    /// chooses to. Without it the Dock is simply not a perch.
    func requestDockAccess() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Allow Dock walking?"
        alert.informativeText = "To walk along the Dock, Notchemon needs Accessibility permission to read the Dock's size and position. It reads nothing else and never controls your Mac. macOS will ask you to turn Notchemon on in Privacy & Security."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Swift 6 rejects reading the kAXTrustedCheckOptionPrompt global as
        // shared mutable state, so its value is spelled out.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        dockWatcher.accessRequested()
    }

    /// macOS ties an Accessibility grant to the signature of the build that
    /// was granted, so a grant to an older or development build shows as on
    /// yet does not apply to this one. The app cannot fix that; it can only say so.
    func explainStaleDockAccess() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Accessibility is on, but Notchemon still won't walk the Dock?"
        alert.informativeText = "macOS keeps an Accessibility grant for the exact build it was made for. A grant to an older or development build of Notchemon shows as on in System Settings but does not apply to this one.\n\nIn Privacy & Security > Accessibility, select Notchemon, remove it with the − button, then add it again or choose Allow Dock Walking… once more."
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openNotesFolder() {
        try? FileManager.default.createDirectory(at: AppPaths.notesFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(AppPaths.notesFolder)
    }
}

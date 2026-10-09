import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let debugSessionSecondsKey = "NotchemonDebugSessionSeconds"
    static let debugSleepSecondsKey = "NotchemonDebugSleepSeconds"

    let presentation = NotchPresentation()
    let party = Party()
    let wild = WildWalker()
    let dockWatcher = DockWatcher()
    let model: CompanionModel
    let notes: FloatingNotes
    private(set) var windowController: NotchWindowController?
    private var dockController: DockWindowController?
    private var hotKey: HotKey?
    private var notesHotKey: HotKey?
    private var cursorNearHome = false
    private var clickMonitor: Any?
    private var sleepObservers: [NSObjectProtocol] = []
    private var hitRefresh: Task<Void, Never>?
    private var hitRefreshAt: Date?
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
            sleepAfter: sleepSeconds > 0 ? sleepSeconds : BehaviourRules.sleepAfter,
            unlockAll: { UnlockOverride.isOn(defaults: .standard, bundleIdentifier: Bundle.main.bundleIdentifier) }
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
            content: NotchRootView(presentation: presentation, model: model, party: party, wild: wild)
        )
        windowController = controller
        dockController = DockWindowController(content: DockRootView(model: model, party: party, wild: wild, dock: dockWatcher))
        controller.onCursorMoved = { [weak self] point in self?.cursorMoved(to: point) }
        controller.wildBox = { [weak self] in self?.wildBox(on: .topEdge) }
        wild.onChange = { [weak self] in
            guard let self else { return }
            refreshExtent()
            showDock()
            windowController?.refreshHitTesting()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, asleep) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false)] {
            sleepObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.setSystemAsleep(asleep) }
            })
        }
        wild.onGone = { [weak self] serial in self?.model.encounterGone(serial) }
        // A click on a visitor catches it and goes no further.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let caught = MainActor.assumeIsolated { self?.catchWild(at: NSEvent.mouseLocation) ?? false }
            return caught ? nil : event
        }
        // Arriving, setting off, or walking up to or past a still cursor moves
        // the creature, not the cursor, so it looks again from where it is.
        // On or bound for the Dock, the Dock may have changed size since the
        // last read, so it is read again here rather than polled.
        party.onLookAgain = { [weak self] roamer in
            guard let self else { return }
            if roamer.phase.touches(.dock) { dockWatcher.refresh() }
            refreshExtent()
            showDock()
            cursorMoved(to: NSEvent.mouseLocation)
        }
        party.onEvent = { [weak self] event in self?.record(event) }
        dockWatcher.onChange = { [weak self] in
            guard let self else { return }
            showDock()
            cursorMoved(to: NSEvent.mouseLocation)
        }
        model.onSnapshot = { [weak self] in
            self?.syncParty()
            self?.refreshRoam()
            self?.syncWild()
        }
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
        let there = party.all.contains { $0.phase.touches(.dock) } || wild.visit?.perch == .dock
        dockController?.show(on: dockWatcher.shelf, creatureThere: there)
    }

    /// The notch window stays wide enough for the whole party and any visitor on the top edge.
    private func refreshExtent() {
        let visitor = wild.visit.map { $0.perch == .topEdge ? $0.farthest : 0 } ?? 0
        let members: Double = party.all.map(\.phase.farthestAlongTopEdge).max() ?? 0
        windowController?.setCreatureExtent(max(members, visitor))
    }

    /// One roamer per member whose frames have loaded; none before a starter is chosen.
    private func syncParty() {
        let snapshot = model.snapshot
        let followers: [Int] = snapshot.leader == nil ? [] : snapshot.followers.map(\.root)
        party.sync(leader: snapshot.leader, followers: followers)
    }

    /// Follows the engine: a new visitor gets a path, a caught one its
    /// catch, and one the engine sent away leaves at once.
    private func syncWild() {
        guard let encounter = model.snapshot.encounter else {
            if wild.serial != nil { wild.end() }
            return
        }
        if wild.serial != encounter.serial, wild.finished != encounter.serial {
            beginWild(encounter)
        } else if encounter.caught {
            wild.catchNow()
        }
    }

    /// The Dock when the creature may walk it and no party member is on
    /// it, else the top edge, in the widest stretch clear of every member
    /// and of home.
    private func beginWild(_ encounter: Encounter) {
        let now = Date()
        let members: [RoamSpot] = party.all.map { $0.phase.heldSpot(at: now) }
        let dock = model.snapshot.preferences.wander.includesDock ? dockWatcher.shelf?.range : nil
        let perch: Perch = dock != nil && !members.contains { $0.perch == .dock } ? .dock : .topEdge
        var range: ClosedRange<Double>?
        var avoiding: [Double] = members.filter { $0.perch == perch }.map(\.x)
        if perch == .dock {
            range = dock
        } else if let screen = NSScreen.notchHost {
            let reach = Double(NotchGeometry.roamReach(.topEdge, screenWidth: screen.frame.width))
            range = -reach...reach
            avoiding.append(0)
        }
        var rng = SystemRandomNumberGenerator()
        guard let range, let span = WildVisit.span(in: range, avoiding: avoiding) else {
            model.encounterGone(encounter.serial)
            return
        }
        wild.begin(WildVisit.plan(on: perch, in: span, start: now, using: &rng), serial: encounter.serial)
    }

    /// The visitor's box on `perch` right now, from its visit's path.
    private func wildBox(on perch: Perch) -> CGRect? {
        guard let visit = wild.visit, visit.perch == perch, !wild.isCaught, let x = visit.x(at: Date()),
              let centre = closedCentre(on: perch, at: x)
        else { return nil }
        return HoverPolicy.wildBox(centre: centre)
    }

    /// A walking visitor can reach or leave a cursor that is not moving, so
    /// the hover rules are asked again when its box's edge passes it.
    private func scheduleHitRefresh(for point: CGPoint) {
        let now = Date()
        var next: Date?
        if let visit = wild.visit, !wild.isCaught, let leg = visit.leg(at: now), case .walk(let walk) = leg.track,
           let origin = closedCentre(on: visit.perch, at: 0) {
            let half = Double(NotchGeometry.peekHeight) / 2
            if abs(point.y - origin.y) <= half {
                let across = CursorOffset(dx: point.x - origin.x, dy: 0)
                next = walk.crossings(of: across, radius: half).first { $0 > now }
            }
        }
        guard next != hitRefreshAt else { return }
        hitRefresh?.cancel()
        hitRefreshAt = next
        guard let next else { return }
        hitRefresh = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)), tolerance: .milliseconds(20))
            guard !Task.isCancelled, let self else { return }
            hitRefreshAt = nil
            windowController?.refreshHitTesting()
        }
    }

    /// Clicks inside the open panel stay the panel's.
    private func catchWild(at point: CGPoint) -> Bool {
        if presentation.isExpanded, presentation.layout?.expanded.contains(point) == true { return false }
        let hit = [Perch.topEdge, .dock].contains { wildBox(on: $0)?.contains(point) == true }
        guard hit, wild.catchNow() else { return false }
        model.catchEncounter()
        return true
    }

    /// Offsets are measured from where each creature is now, mid-walk and on
    /// the Dock too, so it faces and hops at the cursor from its own spot. A
    /// cursor near home calls the leader running back to greet it.
    private func cursorMoved(to point: CGPoint) {
        dockWatcher.cursorMoved(to: point)
        dockController?.setTakesClicks(wildBox(on: .dock)?.contains(point) == true)
        scheduleHitRefresh(for: point)
        guard let layout = presentation.layout, let metrics = presentation.metrics else {
            for roamer in party.all { roamer.watch(nil) }
            refreshRoam()
            return
        }
        let home = metrics.spriteCentre(expanded: false, roamX: 0, panelFrame: layout.expanded)
        cursorNearHome = hypot(point.x - home.x, point.y - home.y) <= BehaviourRules.watchRadius
        for roamer in party.all {
            let perchOrigin = closedCentre(on: roamer.phase.perch, at: 0) ?? home
            roamer.watch(CursorOffset(dx: point.x - perchOrigin.x, dy: point.y - perchOrigin.y))
        }
        refreshRoam()
        party.cursorMoved(to: point, hopsEnabled: model.snapshot.preferences.hopsOnApproach) { spot in
            closedCentre(on: spot.perch, at: spot.x)
        }
        let expanded = presentation.isExpanded
        let spot = (party.leaderRoamer?.phase ?? .home).spot(at: Date())
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

    private func record(_ event: CompanionEvent) {
        var millimetres = 0.0
        if case .walked(_, let perch, _) = event { millimetres = screenMillimetresPerPoint(on: perch) }
        model.record(event, screenMillimetresPerPoint: millimetres)
    }

    /// Measured on the display the perch is on, which may not be the notch's.
    private func screenMillimetresPerPoint(on perch: Perch) -> Double {
        let screen: NSScreen? = switch perch {
        case .topEdge: NSScreen.notchHost
        case .dock: NSScreen.screens.first { $0.frame == dockWatcher.shelf?.screen }
        }
        guard let screen, let id = screen.displayID else { return 0 }
        let physical: CGSize = CGDisplayScreenSize(id)
        return Distance.screenMillimetresPerPoint(physicalWidth: Double(physical.width), widthInPoints: Double(screen.frame.width))
    }

    /// The leader first, so followers deciding after it see where it went.
    private func refreshRoam() {
        let snapshot = model.snapshot
        model.setFullScreen(presentation.isFullScreen)
        let reach = Double(presentation.layout?.roamReach ?? 0)
        for roamer in party.all {
            let conditions = HomingConditions(
                wander: snapshot.preferences.wander,
                panelOpen: presentation.isExpanded,
                sleeping: snapshot.behaviour == .sleeping,
                focusing: snapshot.focus != nil,
                fullScreen: presentation.isFullScreen,
                cursorNearHome: cursorNearHome,
                hasCreature: model.activeSpecies != nil,
                perch: roamer.phase.perch,
                visitor: snapshot.encounter != nil,
                leads: roamer.partner == party.leader
            )
            roamer.update(range: -reach...reach, dock: dockWatcher.shelf?.range, homing: RoamRules.homing(conditions))
        }
    }

    func showPartners() {
        model.showPartners()
        windowController?.expandPinned(focusNote: false)
    }

    /// Writes this build's own defaults domain, which the override reads.
    func setUnlockAll(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: UnlockOverride.defaultsKey)
        model.refreshUnlocks()
    }

    func confirmResetCollection() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Reset the collection?"
        alert.informativeText = "Every partner and its level and XP will be removed, and you will choose a starter again. Stats are kept. This cannot be undone."
        alert.addButton(withTitle: "Reset Collection")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.resetCollection()
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

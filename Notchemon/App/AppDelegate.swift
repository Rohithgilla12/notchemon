import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let debugSessionSecondsKey = "NotchemonDebugSessionSeconds"
    static let debugSleepSecondsKey = "NotchemonDebugSleepSeconds"

    let presentation = NotchPresentation()
    let roamer = Roamer()
    let dockWatcher = DockWatcher()
    let model: CompanionModel
    private(set) var windowController: NotchWindowController?
    private var dockController: DockWindowController?
    private var hotKey: HotKey?
    private var cursorNearHome = false

    override init() {
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
            content: NotchRootView(presentation: presentation, model: model, roamer: roamer)
        )
        windowController = controller
        dockController = DockWindowController(content: DockRootView(model: model, roamer: roamer))
        controller.onCursorMoved = { [weak self] point in self?.cursorMoved(to: point) }
        // Arriving, setting off, or walking up to or past a still cursor moves
        // the creature, not the cursor, so it looks again from where it is.
        // On or bound for the Dock, the Dock may have changed size since the
        // last read, so it is read again here and nowhere on a timer.
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
            self?.dockWatcher.setWanted(preferences.wander.includesDock)
        }
        model.onChoosingStarter = { [weak controller] in
            controller?.expandPinned(focusNote: false)
        }
        controller.start()
        dockWatcher.start(wanted: model.snapshot.preferences.wander.includesDock)
        hotKey = HotKey.controlOptionN { [weak controller] in controller?.toggleFromHotkey() }
        Task { await model.run() }
    }

    private func showDock() {
        dockController?.show(on: dockWatcher.shelf, creatureThere: roamer.phase.touches(.dock))
    }

    /// Offsets are measured from where the creature is now, mid-walk and on
    /// the Dock too, so it faces and hops at the cursor from its own spot. A
    /// cursor near home calls it running back to greet it.
    private func cursorMoved(to point: CGPoint) {
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
            hasCreature: model.activeSpecies != nil
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

    func openNotesFolder() {
        try? FileManager.default.createDirectory(at: AppPaths.notesFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(AppPaths.notesFolder)
    }
}

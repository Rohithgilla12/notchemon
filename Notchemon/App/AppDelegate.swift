import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let debugSessionSecondsKey = "NotchemonDebugSessionSeconds"
    static let debugSleepSecondsKey = "NotchemonDebugSleepSeconds"

    let presentation = NotchPresentation()
    let roamer = Roamer()
    let model: CompanionModel
    private(set) var windowController: NotchWindowController?
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
        controller.onCursorMoved = { [weak self] point in self?.cursorMoved(to: point) }
        // Arriving or setting off moves the creature, not the cursor, so it looks again from where it is.
        roamer.onPhaseChanged = { [weak self] in self?.cursorMoved(to: NSEvent.mouseLocation) }
        model.onSnapshot = { [weak self] in self?.refreshRoam() }
        model.onPreferencesChanged = { [weak controller] preferences in
            controller?.setVirtualNotchEnabled(preferences.virtualNotchEnabled)
            controller?.setWander(preferences.wander)
        }
        model.onChoosingStarter = { [weak controller] in
            controller?.expandPinned(focusNote: false)
        }
        controller.start()
        hotKey = HotKey.controlOptionN { [weak controller] in controller?.toggleFromHotkey() }
        Task { await model.run() }
    }

    /// Offsets are measured from where the creature is now, mid-walk too, so
    /// it faces and hops at the cursor from its own spot. A cursor near home
    /// calls it running back to greet it.
    private func cursorMoved(to point: CGPoint) {
        guard let layout = presentation.layout, let metrics = presentation.metrics else {
            refreshRoam()
            return
        }
        let home = metrics.spriteCentre(expanded: false, roamX: 0, panelFrame: layout.expanded)
        cursorNearHome = hypot(point.x - home.x, point.y - home.y) <= BehaviourRules.watchRadius
        refreshRoam()
        let expanded = presentation.isExpanded
        let centre = metrics.spriteCentre(expanded: expanded, roamX: roamer.phase.x(at: Date()), panelFrame: layout.expanded)
        model.cursorMoved(to: point, spriteCentre: centre, panelExpanded: expanded)
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
        roamer.update(range: -reach...reach, homing: RoamRules.homing(conditions))
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

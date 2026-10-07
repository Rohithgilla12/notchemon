import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let debugSessionSecondsKey = "NotchemonDebugSessionSeconds"
    static let debugSleepSecondsKey = "NotchemonDebugSleepSeconds"

    let presentation = NotchPresentation()
    let model: CompanionModel
    private(set) var windowController: NotchWindowController?
    private var hotKey: HotKey?

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
            content: NotchRootView(presentation: presentation, model: model)
        )
        windowController = controller
        controller.onCursorMoved = { [presentation, model] point in
            guard let layout = presentation.layout, let metrics = presentation.metrics else { return }
            let frame = metrics.spriteFrame(expanded: presentation.isExpanded)
            let centre = metrics.screenPoint(CGPoint(x: frame.midX, y: frame.midY), panelFrame: layout.expanded)
            model.cursorMoved(to: point, spriteCentre: centre, panelExpanded: presentation.isExpanded)
        }
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

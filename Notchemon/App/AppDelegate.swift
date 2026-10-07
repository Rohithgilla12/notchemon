import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let presentation = NotchPresentation()
    private var windowController: NotchWindowController?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The test bundle is hosted in the app; tests must not open panels or touch user state.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let controller = NotchWindowController(
            presentation: presentation,
            virtualNotchEnabled: true,
            content: NotchRootView(presentation: presentation)
        )
        windowController = controller
        controller.start()
        hotKey = HotKey.controlOptionN { [weak controller] in controller?.toggleFromHotkey() }
    }
}

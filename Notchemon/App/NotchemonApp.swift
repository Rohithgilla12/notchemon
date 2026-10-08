import SwiftUI

@main
struct NotchemonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let updater = AppUpdater()

    var body: some Scene {
        MenuBarExtra("Notchemon", systemImage: "sparkles") {
            MenuBarContent(app: delegate, model: delegate.model)
                .environment(updater)
        }
    }
}

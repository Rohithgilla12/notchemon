import SwiftUI

@main
struct NotchemonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Notchemon", systemImage: "sparkles") {
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}

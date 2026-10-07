import SwiftUI

@main
struct NotchemonApp: App {
    var body: some Scene {
        MenuBarExtra("Notchemon", systemImage: "sparkles") {
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}

import SwiftUI

struct AppMenuSection: View {
    @Environment(AppUpdater.self) private var updater
    @Environment(LoginItem.self) private var loginItem

    var body: some View {
        Button("About Notchemon", action: AboutWindow.show)
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!updater.canCheckForUpdates)
        switch loginItem.state {
        case .off, .on:
            Toggle("Launch at Login", isOn: Binding(get: { loginItem.state == .on }, set: { _ in loginItem.toggle() }))
        case .needsApproval:
            Button("Allow Launch at Login in System Settings…", action: loginItem.toggle)
        }
    }
}

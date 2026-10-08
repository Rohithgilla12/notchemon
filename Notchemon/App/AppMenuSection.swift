import SwiftUI

struct AppMenuSection: View {
    @Environment(AppUpdater.self) private var updater

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!updater.canCheckForUpdates)
    }
}

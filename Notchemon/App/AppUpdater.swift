import AppKit
import Observation
import Sparkle

/// Sparkle's standard updater, started only in a build that carries an EdDSA
/// public key. Sparkle asks the user about automatic checks on second launch.
@MainActor
@Observable
final class AppUpdater {
    private(set) var canCheckForUpdates = false
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(bundle: Bundle = .main) {
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        guard Self.hasPublicKey(bundle.infoDictionary ?? [:]), !underTest else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    /// Without a key, Sparkle would show a "failed to start" alert at every
    /// launch, so a build made before the one-time key setup skips Sparkle.
    nonisolated static func hasPublicKey(_ info: [String: Any]) -> Bool {
        guard let key = info["SUPublicEDKey"] as? String else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

import AppKit
import ApplicationServices
import Observation

/// Reads where the Dock is. Its frame needs Accessibility permission;
/// without it the frame reads as nil and nothing prompts.
enum DockReader {
    static let bundleIdentifier = "com.apple.dock"

    static func shelf() -> DockShelf? {
        DockGeometry.shelf(reading(), screens: NSScreen.screens.map(\.frame))
    }

    static func reading() -> DockReading {
        // A fresh suite each time: an instance can serve values cached from
        // before the Dock last wrote them.
        let defaults = UserDefaults(suiteName: bundleIdentifier)
        // The Dock writes no orientation key until it is moved off the bottom.
        let orientation = defaults?.string(forKey: "orientation").flatMap(DockOrientation.init(rawValue:)) ?? .bottom
        return DockReading(listFrame: listFrame(), orientation: orientation, autoHides: defaults?.bool(forKey: "autohide") ?? false)
    }

    /// The Dock's icon list, which spans its whole visible shelf.
    private static func listFrame() -> CGRect? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
              let primary = NSScreen.screens.first
        else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        // A busy Dock would otherwise hold the main thread for the default six seconds.
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let children: [AXUIElement] = attribute(kAXChildrenAttribute, of: app),
              let list = children.first(where: { (attribute(kAXRoleAttribute, of: $0) as String?) == kAXListRole }),
              let position: AXValue = attribute(kAXPositionAttribute, of: list),
              let size: AXValue = attribute(kAXSizeAttribute, of: list)
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        return DockGeometry.appKitFrame(axPosition: origin, size: extent, primaryHeight: primary.frame.height)
    }

    private static func attribute<Value>(_ name: String, of element: AXUIElement) -> Value? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? Value
    }
}

/// Keeps the Dock's shelf current while the wander setting includes the
/// Dock. It reads only when asked or when something that moves or resizes
/// the Dock happens, never on a timer.
@MainActor
@Observable
final class DockWatcher {
    private(set) var shelf: DockShelf?
    private(set) var isTrusted = AXIsProcessTrusted()
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    func start(wanted: Bool) {
        self.wanted = wanted
        // Launching or quitting an app adds or drops a Dock icon, which resizes the Dock.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observe(workspace, name) { $0.refresh() }
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.refresh() }
        observe(.default, NSApplication.didBecomeActiveNotification) { $0.recheckTrust() }
        // Posted when any app's Accessibility grant changes. The new grant
        // can take a moment to show in AXIsProcessTrusted, so check once more after it.
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.accessibility.api")) { watcher in
            watcher.recheckTrust()
            Task { @MainActor [weak watcher] in
                try? await Task.sleep(for: .milliseconds(500))
                watcher?.recheckTrust()
            }
        }
        refresh()
    }

    func setWanted(_ wanted: Bool) {
        guard wanted != self.wanted else { return }
        self.wanted = wanted
        refresh()
    }

    /// Reads the Dock again. Cheap once the Accessibility connection is up,
    /// but still a round trip to the Dock, so callers ask only at moments
    /// the creature is on it or heading there.
    func refresh() {
        let next = wanted && isTrusted ? DockReader.shelf() : nil
        guard next != shelf else { return }
        shelf = next
        onChange?()
    }

    func recheckTrust() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        refresh()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handle: @escaping @MainActor (DockWatcher) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handle(self)
            }
        }
        observers.append(token)
    }
}

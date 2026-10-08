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
/// Dock. It reads only when asked or when something that moves, resizes,
/// shows, or hides the Dock happens. Nothing runs between those.
@MainActor
@Observable
final class DockWatcher {
    private(set) var shelf: DockShelf?
    private(set) var isTrusted: Bool
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let read: @MainActor () -> DockShelf?
    @ObservationIgnored private let trusted: () -> Bool
    @ObservationIgnored private var cursor: CGPoint?
    /// Reads that follow an auto-hiding Dock through one slide.
    @ObservationIgnored private var confirming: Task<Void, Never>?
    /// What the cursor last called for that a whole confirm could not see
    /// happen, so moving on without changing that call reads nothing more.
    @ObservationIgnored private var gaveUpOn: Bool?

    /// The Dock's Accessibility elements send no move notification as it
    /// slides (registering for one fails as unsupported), so a slide is
    /// confirmed by reading the Dock this long after the cursor sets one
    /// off, then every `confirmStep` until it stops, up to `confirmReads` times.
    static let confirmDelay: Duration = .milliseconds(300)
    static let confirmStep: Duration = .milliseconds(100)
    static let confirmReads = 8

    init(read: @escaping @MainActor () -> DockShelf? = DockReader.shelf, trusted: @escaping () -> Bool = AXIsProcessTrusted) {
        self.read = read
        self.trusted = trusted
        isTrusted = trusted()
    }

    func start(wanted: Bool) {
        self.wanted = wanted
        // Launching or quitting an app adds or drops a Dock icon, which resizes the Dock.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observe(workspace, name) { $0.refresh() }
        }
        // Clicking an app in a shown auto-hiding Dock can hide it with the cursor still over it.
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { watcher in
            if watcher.shelf?.autoHide?.slide == .shown { watcher.confirmSlide() }
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
        let next = wanted && isTrusted ? read() : nil
        guard next != shelf else { return }
        shelf = next
        onChange?()
    }

    /// Called on every cursor move, so it reads nothing unless the cursor
    /// calls for an auto-hiding Dock to be shown and it is not, or the reverse.
    func cursorMoved(to point: CGPoint) {
        cursor = point
        guard let shows = cursorShowsDock else { return }
        if shows != gaveUpOn { gaveUpOn = nil }
        guard shows != (shelf?.autoHide?.slide == .shown), gaveUpOn == nil else { return }
        confirmSlide()
    }

    /// Whether the cursor calls for an auto-hiding Dock to be shown, or nil
    /// when there is no such Dock or no cursor seen yet.
    private var cursorShowsDock: Bool? {
        cursor.flatMap { shelf?.cursorShowsDock($0) }
    }

    /// Reads the Dock through one slide, until it has stopped and either
    /// moved from where it was or agrees with the cursor. A Dock that slid
    /// one way but should now slide back is followed by another confirm.
    private func confirmSlide() {
        guard confirming == nil, let from = shelf?.autoHide?.slide else { return }
        confirming = Task { [weak self] in
            try? await Task.sleep(for: Self.confirmDelay)
            var settled = false
            for read in 1...Self.confirmReads {
                guard let self else { return }
                refresh()
                guard let slide = shelf?.autoHide?.slide else { break }
                settled = slide != .sliding && (slide != from || (slide == .shown) == cursorShowsDock)
                if settled || read == Self.confirmReads { break }
                try? await Task.sleep(for: Self.confirmStep)
            }
            guard let self else { return }
            confirming = nil
            if settled {
                gaveUpOn = nil
                if let cursor { cursorMoved(to: cursor) }
            } else {
                gaveUpOn = cursorShowsDock
            }
        }
    }

    func recheckTrust() {
        let granted = trusted()
        guard granted != isTrusted else { return }
        isTrusted = granted
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

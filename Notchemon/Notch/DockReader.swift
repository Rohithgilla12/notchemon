import AppKit
import ApplicationServices
import Observation

/// Reads where the Dock is. Its frame needs Accessibility permission;
/// without it the Dock is unreadable and nothing prompts.
enum DockReader {
    static let bundleIdentifier = "com.apple.dock"

    /// Accessibility gave no frame for the Dock: it timed out, was refused,
    /// or the Dock was not running.
    struct Unreadable: Error {}

    /// The shelf, or nil when the Dock answered but offers none.
    static func shelf() throws -> DockShelf? {
        let reading = reading()
        guard reading.listFrame != nil else { throw Unreadable() }
        return DockGeometry.shelf(reading, screens: NSScreen.screens.map(\.frame))
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
/// shows, or hides the Dock happens, and retries a read the Dock did not
/// answer at most `retryDelays.count` times. Nothing runs between those.
@MainActor
@Observable
final class DockWatcher {
    private(set) var shelf: DockShelf?
    private(set) var isTrusted: Bool
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let read: @MainActor () throws -> DockShelf?
    @ObservationIgnored private let trusted: () -> Bool
    @ObservationIgnored private let after: After
    @ObservationIgnored private var cursor: CGPoint?
    /// Whether reads are following an auto-hiding Dock through one slide.
    @ObservationIgnored private var confirming = false
    /// What the cursor last called for that a whole confirm could not see
    /// happen, so moving on without changing that call reads nothing more.
    @ObservationIgnored private var gaveUpOn: Bool?
    /// Retries spent since the Dock last answered, or nil while it answers.
    @ObservationIgnored private var retriesSpent: Int?
    @ObservationIgnored private var retryDue = false

    /// The Dock's Accessibility elements send no move notification as it
    /// slides (registering for one fails as unsupported), so a slide is
    /// confirmed by reading the Dock this long after the cursor sets one
    /// off, then every `confirmStep` until it stops, up to `confirmReads` times.
    static let confirmDelay: Duration = .milliseconds(300)
    static let confirmStep: Duration = .milliseconds(100)
    static let confirmReads = 8
    /// How long after each read the Dock did not answer it is read again. An
    /// app launch can keep the Dock too busy to answer, and a relaunched Dock
    /// takes a moment before it can.
    static let retryDelays: [Duration] = [.seconds(1), .seconds(3)]

    /// Runs work on the main actor once a delay has passed. Tests pass one they move on by hand.
    typealias After = @MainActor (Duration, @escaping @MainActor @Sendable () -> Void) -> Void

    init(
        read: @escaping @MainActor () throws -> DockShelf? = DockReader.shelf,
        trusted: @escaping () -> Bool = AXIsProcessTrusted,
        after: @escaping After = DockWatcher.afterSleeping
    ) {
        self.read = read
        self.trusted = trusted
        self.after = after
        isTrusted = trusted()
    }

    static func afterSleeping(_ delay: Duration, _ work: @escaping @MainActor @Sendable () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            work()
        }
    }

    func start(wanted: Bool) {
        self.wanted = wanted
        // Launching or quitting an app adds or drops a Dock icon, which resizes the Dock.
        let workspace = NSWorkspace.shared.notificationCenter
        let launches = workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let launched = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.applicationLaunched(bundleIdentifier: launched) }
        }
        observers.append(launches)
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { $0.refresh() }
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
            watcher.after(.milliseconds(500)) { [weak watcher] in watcher?.recheckTrust() }
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
        var next: DockShelf?
        if wanted && isTrusted {
            do {
                next = try read()
                retriesSpent = nil
            } catch {
                readAgain()
            }
        } else {
            retriesSpent = nil
        }
        guard next != shelf else { return }
        shelf = next
        onChange?()
    }

    /// Reads the Dock once a retry delay has passed, unless a retry is
    /// already due or every one has been spent since the Dock last answered.
    private func readAgain() {
        let spent = retriesSpent ?? 0
        retriesSpent = spent
        guard !retryDue, spent < Self.retryDelays.count else { return }
        retriesSpent = spent + 1
        retryDue = true
        after(Self.retryDelays[spent]) { [weak self] in
            guard let self else { return }
            retryDue = false
            if retriesSpent != nil { refresh() }
        }
    }

    func applicationLaunched(bundleIdentifier: String?) {
        refresh()
        // A relaunched Dock is announced as it starts, which can be before it
        // answers Accessibility or has laid out its icons.
        if bundleIdentifier == DockReader.bundleIdentifier { readAgain() }
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
        guard !confirming, let from = shelf?.autoHide?.slide else { return }
        confirming = true
        after(Self.confirmDelay) { [weak self] in self?.confirmRead(1, from: from) }
    }

    private func confirmRead(_ read: Int, from: AutoHidingDock.Slide) {
        refresh()
        guard let slide = shelf?.autoHide?.slide else { return finishConfirm(settled: false) }
        let settled = slide != .sliding && (slide != from || (slide == .shown) == cursorShowsDock)
        if settled || read == Self.confirmReads { return finishConfirm(settled: settled) }
        after(Self.confirmStep) { [weak self] in self?.confirmRead(read + 1, from: from) }
    }

    private func finishConfirm(settled: Bool) {
        confirming = false
        if settled {
            gaveUpOn = nil
            if let cursor { cursorMoved(to: cursor) }
        } else {
            gaveUpOn = cursorShowsDock
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

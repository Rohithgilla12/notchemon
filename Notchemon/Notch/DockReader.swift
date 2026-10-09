import AppKit
import ApplicationServices
import Observation
import os

/// Trust transitions, each trust check, and shelf changes. Nothing per cursor move.
/// Read with `log show --info --predicate 'subsystem == "com.rohithgilla.Notchemon"'`.
let dockLog = Logger(subsystem: "com.rohithgilla.Notchemon", category: "dock")

/// Which call answered whether this process may read the Dock.
enum TrustSource: String {
    case axIsProcessTrusted
    case probeRead
}

struct TrustCheck: Equatable {
    let trusted: Bool
    let source: TrustSource
}

/// Reads where the Dock is. Its frame needs Accessibility permission;
/// without it the Dock is unreadable and nothing prompts.
enum DockReader {
    static let bundleIdentifier = "com.apple.dock"

    /// Whether this process may read the Dock right now. `AXIsProcessTrusted`
    /// is asked first, but a no from it is not final: 0.2.2 asked only it and
    /// a running copy never saw a grant that worked at once after a relaunch,
    /// so a real Accessibility read of the Dock decides.
    static func checkTrust(axTrusted: () -> Bool = AXIsProcessTrusted, probe: () -> AXError = probeDock) -> TrustCheck {
        if axTrusted() { return TrustCheck(trusted: true, source: .axIsProcessTrusted) }
        return TrustCheck(trusted: probe() == .success, source: .probeRead)
    }

    static func isTrusted() -> Bool {
        let check = checkTrust()
        dockLog.info("trust check: \(check.trusted) via \(check.source.rawValue, privacy: .public)")
        return check.trusted
    }

    /// One read of the Dock's children. `.apiDisabled` means untrusted;
    /// `.success` means trusted whatever `AXIsProcessTrusted` says.
    static func probeDock() -> AXError {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else { return .cannotComplete }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, Float(DockReadBudget.total))
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &value)
    }

    static func read() -> DockRead {
        DockGeometry.read(reading(), screens: NSScreen.screens.map(\.frame), isFullScreen: FullScreenDetector.isFullScreen(screenFrame:))
    }

    static func reading() -> DockReading {
        // A fresh suite each time: an instance can serve values cached from
        // before the Dock last wrote them.
        let defaults = UserDefaults(suiteName: bundleIdentifier)
        // The Dock writes no orientation key until it is moved off the bottom.
        let orientation = defaults?.string(forKey: "orientation").flatMap(DockOrientation.init(rawValue:)) ?? .bottom
        return DockReading(listFrame: listFrame(), orientation: orientation, autoHides: defaults?.bool(forKey: "autohide") ?? false)
    }

    /// At most this many of the Dock's top-level elements are checked for its icon list.
    static let childrenChecked = 4

    /// The Dock's icon list, which spans its whole visible shelf. `checkTrust`
    /// decides trust, so no `AXIsProcessTrusted` guard here; an untrusted
    /// read fails on its own.
    private static func listFrame() -> CGRect? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
              let primary = NSScreen.screens.first
        else { return nil }
        let budget = DockReadBudget(startingAt: ProcessInfo.processInfo.systemUptime)
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        guard let children: [AXUIElement] = attribute(kAXChildrenAttribute, of: app, within: budget),
              let list = children.prefix(childrenChecked).first(where: { (attribute(kAXRoleAttribute, of: $0, within: budget) as String?) == kAXListRole }),
              let position: AXValue = attribute(kAXPositionAttribute, of: list, within: budget),
              let size: AXValue = attribute(kAXSizeAttribute, of: list, within: budget)
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        return DockGeometry.appKitFrame(axPosition: origin, size: extent, primaryHeight: primary.frame.height)
    }

    private static func attribute<Value>(_ name: String, of element: AXUIElement, within budget: DockReadBudget) -> Value? {
        guard let timeout = budget.timeout(at: ProcessInfo.processInfo.systemUptime) else { return nil }
        // A timeout holds only for the element it is set on, and the elements
        // the Dock hands out start at the six-second default.
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? Value
    }
}

/// Bounds how long one read of the Dock can hold the main thread, however
/// many Accessibility calls it makes or how slowly a busy Dock answers them.
struct DockReadBudget {
    static let total: TimeInterval = 0.5
    /// A timeout of zero means the six-second default, so a call is not
    /// started with less than this left.
    static let shortestCall: TimeInterval = 0.01

    let deadline: TimeInterval

    init(startingAt now: TimeInterval) {
        deadline = now + Self.total
    }

    /// How long the next call may wait, or nil once the read is out of time.
    func timeout(at now: TimeInterval) -> Float? {
        let left = deadline - now
        return left >= Self.shortestCall ? Float(left) : nil
    }
}

/// Keeps the Dock's shelf current while the wander setting includes the
/// Dock. It reads only when asked or when something that moves, resizes,
/// shows, or hides the Dock happens, and retries a read the Dock did not
/// answer at most `retryDelays.count` times. Nothing runs between those,
/// except a slow check for Accessibility while that is wanted and missing.
@MainActor
@Observable
final class DockWatcher {
    /// The last read while the Dock was wanted and the process trusted, else nil.
    private(set) var lastRead: DockRead?
    private(set) var isTrusted: Bool
    @ObservationIgnored var onChange: (() -> Void)?

    var shelf: DockShelf? { lastRead?.shelf }

    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let read: @MainActor () -> DockRead
    @ObservationIgnored private let trusted: () -> Bool
    @ObservationIgnored private let after: After
    @ObservationIgnored private var cursor: CGPoint?
    @ObservationIgnored private var trustCheckDue = false
    /// Bumped to disown a check already due.
    @ObservationIgnored private var trustCheckSerial = 0
    /// Quick trust checks left since the user last asked for Accessibility.
    @ObservationIgnored private var quickTrustChecksLeft = 0
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
    /// An Accessibility grant made in System Settings reaches a menu-bar app
    /// through no notification it can count on, so while the Dock is wanted
    /// and the process is untrusted, trust is checked this often. For
    /// `quickTrustChecks` checks after the user asks for access it is
    /// checked every `quickTrustCheck` instead.
    static let trustCheck: Duration = .seconds(30)
    static let quickTrustCheck: Duration = .seconds(2)
    static let quickTrustChecks = 60

    /// Runs work on the main actor once a delay has passed. Tests pass one they move on by hand.
    typealias After = @MainActor (Duration, @escaping @MainActor @Sendable () -> Void) -> Void

    init(
        read: @escaping @MainActor () -> DockRead = DockReader.read,
        trusted: @escaping () -> Bool = DockReader.isTrusted,
        after: @escaping After = DockWatcher.afterSleeping
    ) {
        self.read = read
        self.trusted = trusted
        self.after = after
        isTrusted = trusted()
    }

    static func afterSleeping(_ delay: Duration, _ work: @escaping @MainActor @Sendable () -> Void) {
        Task { @MainActor in
            // A tenth of the delay lets the system batch long timers, and is
            // within what a Dock slide or a trust check can bear.
            try? await Task.sleep(for: delay, tolerance: delay / 10)
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
        // Entering or leaving a full-screen app switches Spaces.
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.refresh() }
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
        var next: DockRead?
        if wanted && isTrusted { next = read() }
        if next == .unreadable {
            readAgain()
        } else {
            retriesSpent = nil
        }
        checkTrustLater()
        guard next != lastRead else { return }
        lastRead = next
        dockLog.info("dock read: \(String(describing: next), privacy: .public)")
        onChange?()
    }

    /// Checks trust once `trustCheck` or `quickTrustCheck` has passed, while
    /// the Dock is wanted and the process untrusted, unless a check is
    /// already due. Nothing is scheduled otherwise.
    private func checkTrustLater() {
        guard wanted, !isTrusted, !trustCheckDue else { return }
        trustCheckDue = true
        let serial = trustCheckSerial
        let quick = quickTrustChecksLeft > 0
        if quick { quickTrustChecksLeft -= 1 }
        after(quick ? Self.quickTrustCheck : Self.trustCheck) { [weak self] in
            guard let self, serial == trustCheckSerial else { return }
            trustCheckDue = false
            guard wanted, !isTrusted else { return }
            recheckTrust()
            checkTrustLater()
        }
    }

    /// The user has just asked macOS for Accessibility, so the grant is
    /// likely to come within the next couple of minutes. A slow check
    /// already due is dropped so the quick ones start now.
    func accessRequested() {
        trustCheckSerial += 1
        trustCheckDue = false
        quickTrustChecksLeft = Self.quickTrustChecks
        recheckTrust()
        checkTrustLater()
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
        dockLog.info("trust changed: \(granted)")
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

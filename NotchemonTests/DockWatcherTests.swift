import CoreGraphics
import Foundation
import Testing
@testable import Notchemon

/// Holds the work a `DockWatcher` schedules until a test moves time on, then
/// runs whatever has come due in order, so nothing waits on the wall clock.
@MainActor
final class ManualTimers {
    private var now: Duration = .zero
    private var pending: [(due: Duration, work: @MainActor @Sendable () -> Void)] = []

    func after(_ delay: Duration, _ work: @escaping @MainActor @Sendable () -> Void) {
        pending.append((now + delay, work))
    }

    func advance(by delay: Duration) {
        let end = now + delay
        while let next = pending.indices.filter({ pending[$0].due <= end }).min(by: { pending[$0].due < pending[$1].due }) {
            let timer = pending.remove(at: next)
            now = timer.due
            timer.work()
        }
        now = end
    }
}

@MainActor
struct DockWatcherTests {
    static let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    static func dock(_ y: CGFloat) -> DockShelf {
        DockGeometry.shelf(DockReading(listFrame: CGRect(x: 120, y: y, width: 1488, height: 90), orientation: .bottom, autoHides: true), screens: [screen])!
    }
    static let hidden = dock(-90)
    static let sliding = dock(-40)
    static let shown = dock(10)

    /// Hands out the Dock as it would read at each successive read, then keeps the last.
    @MainActor
    final class Dock {
        enum Answer {
            case shelf(DockShelf?)
            case unreadable
        }

        var script: [Answer]
        var reads = 0

        init(_ shelves: DockShelf?...) {
            script = shelves.map(Answer.shelf)
        }

        init(answers: Answer...) {
            script = answers
        }

        func read() throws -> DockShelf? {
            reads += 1
            switch script.count > 1 ? script.removeFirst() : script.first ?? .shelf(nil) {
            case .shelf(let shelf): return shelf
            case .unreadable: throw DockReader.Unreadable()
            }
        }
    }

    let timers = ManualTimers()

    func watcher(_ dock: Dock) -> DockWatcher {
        let watcher = DockWatcher(read: dock.read, trusted: { true }, after: timers.after)
        watcher.setWanted(true)
        return watcher
    }

    @Test func cursorMovesAwayFromTheBottomEdgeReadNothing() {
        let dock = Dock(Self.hidden)
        let watcher = watcher(dock)
        for y in stride(from: 900.0, through: 4, by: -40) { watcher.cursorMoved(to: CGPoint(x: 600, y: y)) }
        timers.advance(by: .seconds(5))
        #expect(dock.reads == 1)
        #expect(watcher.shelf == Self.hidden)
    }

    @Test func reachingTheBottomEdgeReadsOnceAfterTheDelayAndShowsTheDock() {
        let dock = Dock(Self.hidden, Self.shown)
        let watcher = watcher(dock)
        for x in stride(from: 600.0, through: 700, by: 10) { watcher.cursorMoved(to: CGPoint(x: x, y: 0.5)) }
        timers.advance(by: DockWatcher.confirmDelay - .milliseconds(1))
        #expect(dock.reads == 1)
        timers.advance(by: .milliseconds(1))
        #expect(dock.reads == 2)
        #expect(watcher.shelf?.step != nil)
        timers.advance(by: .seconds(5))
        #expect(dock.reads == 2)
    }

    @Test func aReadPartWayThroughTheSlideReadsAgainUntilItStops() {
        let dock = Dock(Self.hidden, Self.sliding, Self.sliding, Self.shown)
        let watcher = watcher(dock)
        watcher.cursorMoved(to: CGPoint(x: 600, y: 1))
        timers.advance(by: DockWatcher.confirmDelay)
        #expect(dock.reads == 2)
        #expect(watcher.shelf?.autoHide?.slide == .sliding)
        #expect(watcher.shelf?.step == nil)
        timers.advance(by: DockWatcher.confirmStep * 2)
        #expect(dock.reads == 4)
        #expect(watcher.shelf?.autoHide?.slide == .shown)
        timers.advance(by: .seconds(5))
        #expect(dock.reads == 4)
    }

    @Test func leavingTheShownDockReadsUntilItHasHidden() {
        let dock = Dock(Self.shown, Self.shown, Self.hidden)
        let watcher = watcher(dock)
        watcher.cursorMoved(to: CGPoint(x: 600, y: 50))
        timers.advance(by: .seconds(5))
        #expect(dock.reads == 1)
        watcher.cursorMoved(to: CGPoint(x: 600, y: 300))
        timers.advance(by: DockWatcher.confirmDelay + DockWatcher.confirmStep)
        #expect(dock.reads == 3)
        #expect(watcher.shelf?.autoHide?.slide == .hidden)
    }

    @Test func aDockThatNeverComesUpIsGivenUpOnUntilTheCursorLeavesTheEdgeAndComesBack() {
        let dock = Dock(Self.hidden)
        let watcher = watcher(dock)
        watcher.cursorMoved(to: CGPoint(x: 600, y: 0))
        timers.advance(by: DockWatcher.confirmDelay + DockWatcher.confirmStep * (DockWatcher.confirmReads - 1))
        #expect(dock.reads == 1 + DockWatcher.confirmReads)
        watcher.cursorMoved(to: CGPoint(x: 900, y: 0))
        timers.advance(by: .seconds(5))
        #expect(dock.reads == 1 + DockWatcher.confirmReads)
        watcher.cursorMoved(to: CGPoint(x: 900, y: 400))
        watcher.cursorMoved(to: CGPoint(x: 900, y: 0))
        timers.advance(by: DockWatcher.confirmDelay)
        #expect(dock.reads == 2 + DockWatcher.confirmReads)
    }

    @Test func aDockThatStaysShownIsNeverReadForTheCursor() {
        let fixed = DockGeometry.shelf(DockReading(listFrame: CGRect(x: 120, y: 0, width: 1488, height: 90), orientation: .bottom, autoHides: false), screens: [Self.screen])
        let dock = Dock(fixed)
        let watcher = watcher(dock)
        watcher.cursorMoved(to: CGPoint(x: 600, y: 0))
        timers.advance(by: .seconds(5))
        #expect(dock.reads == 1)
    }

    @Test func anUnreadableDockIsReadAgainAfterOneSecondAndThreeMoreThenLeftAlone() {
        let dock = Dock(answers: .unreadable)
        let watcher = watcher(dock)
        #expect(watcher.shelf == nil)
        timers.advance(by: .milliseconds(999))
        #expect(dock.reads == 1)
        timers.advance(by: .milliseconds(1))
        #expect(dock.reads == 2)
        timers.advance(by: .milliseconds(2999))
        #expect(dock.reads == 2)
        timers.advance(by: .milliseconds(1))
        #expect(dock.reads == 3)
        timers.advance(by: .seconds(600))
        #expect(dock.reads == 3)
        #expect(watcher.shelf == nil)
    }

    @Test func aDockThatAnswersARetryIsAShelfAgainAndIsNotReadFurther() {
        let dock = Dock(answers: .unreadable, .shelf(Self.hidden))
        let watcher = watcher(dock)
        var changes = 0
        watcher.onChange = { changes += 1 }
        timers.advance(by: .seconds(1))
        #expect(watcher.shelf == Self.hidden)
        #expect(changes == 1)
        timers.advance(by: .seconds(600))
        #expect(dock.reads == 2)
    }

    @Test func aDockThatAnswersWithNoShelfIsNotRetried() {
        let dock = Dock(nil)
        _ = watcher(dock)
        timers.advance(by: .seconds(600))
        #expect(dock.reads == 1)
    }

    @Test func aRetryDueAfterTheDockIsNoLongerWantedReadsNothing() {
        let dock = Dock(answers: .unreadable)
        let watcher = watcher(dock)
        watcher.setWanted(false)
        timers.advance(by: .seconds(600))
        #expect(dock.reads == 1)
    }

    @Test func failuresWhileARetryIsDueAddNoMoreRetries() {
        let dock = Dock(answers: .unreadable)
        let watcher = watcher(dock)
        for _ in 0..<5 { watcher.refresh() }
        #expect(dock.reads == 6)
        timers.advance(by: .seconds(600))
        #expect(dock.reads == 8)
    }

    @Test func theDockLaunchingIsReadAtOnceAndAgainASecondLater() {
        let dock = Dock(answers: .shelf(nil), .shelf(nil), .shelf(Self.hidden))
        let watcher = watcher(dock)
        watcher.applicationLaunched(bundleIdentifier: DockReader.bundleIdentifier)
        #expect(dock.reads == 2)
        #expect(watcher.shelf == nil)
        timers.advance(by: .seconds(1))
        #expect(dock.reads == 3)
        #expect(watcher.shelf == Self.hidden)
        timers.advance(by: .seconds(600))
        #expect(dock.reads == 3)
    }

    @Test func anotherAppLaunchingIsReadOnceAtOnce() {
        let dock = Dock(Self.hidden)
        let watcher = watcher(dock)
        watcher.applicationLaunched(bundleIdentifier: "com.example.Editor")
        #expect(dock.reads == 2)
        timers.advance(by: .seconds(600))
        #expect(dock.reads == 2)
    }
}

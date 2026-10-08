import CoreGraphics
import Foundation
import Testing
@testable import Notchemon

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
        var script: [DockShelf?]
        var reads = 0

        init(_ script: DockShelf?...) {
            self.script = script
        }

        func read() -> DockShelf? {
            reads += 1
            return script.count > 1 ? script.removeFirst() : script.first ?? nil
        }
    }

    func watcher(_ dock: Dock) -> DockWatcher {
        let watcher = DockWatcher(read: dock.read, trusted: { true })
        watcher.setWanted(true)
        return watcher
    }

    /// Past the first confirm read, with time for a frame or two of slack.
    let afterFirstRead: Duration = DockWatcher.confirmDelay + .milliseconds(50)

    @Test func cursorMovesAwayFromTheBottomEdgeReadNothing() async throws {
        let dock = Dock(Self.hidden)
        let watcher = watcher(dock)
        for y in stride(from: 900.0, through: 4, by: -40) { watcher.cursorMoved(to: CGPoint(x: 600, y: y)) }
        try await Task.sleep(for: afterFirstRead + .milliseconds(200))
        #expect(dock.reads == 1)
        #expect(watcher.shelf == Self.hidden)
    }

    @Test func reachingTheBottomEdgeReadsOnceAfterTheDelayAndShowsTheDock() async throws {
        let dock = Dock(Self.hidden, Self.shown)
        let watcher = watcher(dock)
        for x in stride(from: 600.0, through: 700, by: 10) { watcher.cursorMoved(to: CGPoint(x: x, y: 0.5)) }
        try await Task.sleep(for: DockWatcher.confirmDelay - .milliseconds(100))
        #expect(dock.reads == 1)
        try await Task.sleep(for: .milliseconds(150))
        #expect(dock.reads == 2)
        #expect(watcher.shelf?.step != nil)
        try await Task.sleep(for: .milliseconds(400))
        #expect(dock.reads == 2)
    }

    @Test func aReadPartWayThroughTheSlideReadsAgainUntilItStops() async throws {
        let dock = Dock(Self.hidden, Self.sliding, Self.sliding, Self.shown)
        let watcher = watcher(dock)
        watcher.cursorMoved(to: CGPoint(x: 600, y: 1))
        try await Task.sleep(for: afterFirstRead)
        #expect(dock.reads == 2)
        #expect(watcher.shelf?.autoHide?.slide == .sliding)
        #expect(watcher.shelf?.step == nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(dock.reads == 4)
        #expect(watcher.shelf?.autoHide?.slide == .shown)
        try await Task.sleep(for: .milliseconds(300))
        #expect(dock.reads == 4)
    }

    @Test func leavingTheShownDockReadsUntilItHasHidden() async throws {
        let dock = Dock(Self.shown, Self.shown, Self.hidden)
        let watcher = watcher(dock)
        watcher.cursorMoved(to: CGPoint(x: 600, y: 50))
        try await Task.sleep(for: afterFirstRead)
        #expect(dock.reads == 1)
        watcher.cursorMoved(to: CGPoint(x: 600, y: 300))
        try await Task.sleep(for: afterFirstRead + .milliseconds(150))
        #expect(dock.reads == 3)
        #expect(watcher.shelf?.autoHide?.slide == .hidden)
    }

    @Test func aDockThatNeverComesUpIsGivenUpOnUntilTheCursorLeavesTheEdgeAndComesBack() async throws {
        let dock = Dock(Self.hidden)
        let watcher = watcher(dock)
        watcher.cursorMoved(to: CGPoint(x: 600, y: 0))
        try await Task.sleep(for: DockWatcher.confirmDelay + DockWatcher.confirmStep * (DockWatcher.confirmReads - 1) + .milliseconds(150))
        #expect(dock.reads == 1 + DockWatcher.confirmReads)
        watcher.cursorMoved(to: CGPoint(x: 900, y: 0))
        try await Task.sleep(for: afterFirstRead)
        #expect(dock.reads == 1 + DockWatcher.confirmReads)
        watcher.cursorMoved(to: CGPoint(x: 900, y: 400))
        watcher.cursorMoved(to: CGPoint(x: 900, y: 0))
        try await Task.sleep(for: afterFirstRead)
        #expect(dock.reads == 2 + DockWatcher.confirmReads)
    }

    @Test func aDockThatStaysShownIsNeverReadForTheCursor() async throws {
        let fixed = DockGeometry.shelf(DockReading(listFrame: CGRect(x: 120, y: 0, width: 1488, height: 90), orientation: .bottom, autoHides: false), screens: [Self.screen])
        let dock = Dock(fixed)
        let watcher = watcher(dock)
        watcher.cursorMoved(to: CGPoint(x: 600, y: 0))
        try await Task.sleep(for: afterFirstRead)
        #expect(dock.reads == 1)
    }
}

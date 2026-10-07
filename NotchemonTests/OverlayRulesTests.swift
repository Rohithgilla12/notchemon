import CoreGraphics
import Testing
@testable import Notchemon

struct ScreenChooserTests {
    let metrics = ScreenMetrics(frame: .zero, safeAreaTop: 0, auxiliaryTopLeftWidth: 0, auxiliaryTopRightWidth: 0, menuBarHeight: 24)

    @Test func prefersBuiltInEvenWhenItIsNotMain() {
        let screens = [
            ScreenCandidate(isBuiltIn: false, isMain: true, metrics: metrics),
            ScreenCandidate(isBuiltIn: true, isMain: false, metrics: metrics),
        ]
        #expect(ScreenChooser.choose(from: screens) == 1)
    }

    @Test func clamshellFallsBackToMain() {
        let screens = [
            ScreenCandidate(isBuiltIn: false, isMain: false, metrics: metrics),
            ScreenCandidate(isBuiltIn: false, isMain: true, metrics: metrics),
        ]
        #expect(ScreenChooser.choose(from: screens) == 1)
    }

    @Test func noScreensChoosesNothing() {
        #expect(ScreenChooser.choose(from: []) == nil)
    }
}

struct HoverPolicyTests {
    let layout = NotchGeometry.layout(
        for: ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            safeAreaTop: 32,
            auxiliaryTopLeftWidth: 764,
            auxiliaryTopRightWidth: 764,
            menuBarHeight: 37
        ),
        virtualNotchEnabled: false
    )!
    let menuBarIcon = CGPoint(x: 1000, y: 1100)
    let onNotch = CGPoint(x: 864, y: 1100)
    let inExpandedOnly = CGPoint(x: 700, y: 1000)

    @Test func cursorBesideNotchLeavesPanelClickThrough() {
        let decision = HoverPolicy.react(to: menuBarIcon, mode: .collapsed, layout: layout)
        #expect(decision == HoverDecision(mode: .collapsed, hitTestable: false, scheduleCollapse: false, hop: false))
    }

    @Test func enteringNotchExpandsAndHops() {
        let decision = HoverPolicy.react(to: onNotch, mode: .collapsed, layout: layout)
        #expect(decision == HoverDecision(mode: .expanded(.hover), hitTestable: true, scheduleCollapse: false, hop: true))
    }

    @Test func expandedPanelStaysWhileCursorIsInsideIt() {
        let decision = HoverPolicy.react(to: inExpandedOnly, mode: .expanded(.hover), layout: layout)
        #expect(decision.mode == .expanded(.hover))
        #expect(decision.hitTestable)
        #expect(!decision.scheduleCollapse)
    }

    @Test func leavingExpandedPanelSchedulesCollapse() {
        let decision = HoverPolicy.react(to: CGPoint(x: 100, y: 100), mode: .expanded(.hover), layout: layout)
        #expect(decision.scheduleCollapse)
        #expect(!decision.hitTestable)
    }

    @Test func pinnedPanelIgnoresDistantCursorUntilVisited() {
        let away = HoverPolicy.react(to: CGPoint(x: 100, y: 100), mode: .expanded(.pinned), layout: layout)
        #expect(away.mode == .expanded(.pinned))
        #expect(!away.scheduleCollapse)
        #expect(!away.hitTestable)
        let visited = HoverPolicy.react(to: inExpandedOnly, mode: .expanded(.pinned), layout: layout)
        #expect(visited.mode == .expanded(.hover))
        #expect(visited.hitTestable)
    }
}

struct FullScreenDetectorTests {
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    @Test func windowFromNotchLineDownIsFullScreen() {
        let window = WindowSnapshot(ownerPID: 2, layer: 0, bounds: CGRect(x: 0, y: 32, width: 1728, height: 1085))
        #expect(FullScreenDetector.isFullScreen(screenBounds: screen, menuBarHeight: 33, windows: [window], ownPID: 1))
    }

    @Test func zoomedWindowBelowMenuBarIsNotFullScreen() {
        let window = WindowSnapshot(ownerPID: 2, layer: 0, bounds: CGRect(x: 0, y: 33, width: 1728, height: 1084))
        #expect(!FullScreenDetector.isFullScreen(screenBounds: screen, menuBarHeight: 33, windows: [window], ownPID: 1))
    }

    @Test func hiddenMenuBarCountsAsFullScreen() {
        #expect(FullScreenDetector.isFullScreen(screenBounds: screen, menuBarHeight: 0, windows: [], ownPID: 1))
    }

    @Test func ownAndOverlayWindowsAreIgnored() {
        let own = WindowSnapshot(ownerPID: 1, layer: 0, bounds: screen)
        let overlay = WindowSnapshot(ownerPID: 2, layer: 25, bounds: screen)
        #expect(!FullScreenDetector.isFullScreen(screenBounds: screen, menuBarHeight: 33, windows: [own, overlay], ownPID: 1))
    }
}

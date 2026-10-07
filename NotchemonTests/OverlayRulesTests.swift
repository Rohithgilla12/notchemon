import CoreGraphics
import Testing
@testable import Notchemon

struct ScreenChooserTests {
    let metrics = ScreenMetrics(frame: .zero, safeAreaTop: 0, auxiliaryTopLeftWidth: 0, auxiliaryTopRightWidth: 0)

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
            auxiliaryTopRightWidth: 764
        ),
        virtualNotchEnabled: false
    )!
    let menuBarIcon = CGPoint(x: 1000, y: 1100)
    let onNotch = CGPoint(x: 864, y: 1100)
    let inExpandedOnly = CGPoint(x: 700, y: 1000)

    @Test func cursorBesideNotchLeavesPanelClickThrough() {
        let decision = HoverPolicy.react(to: menuBarIcon, mode: .collapsed, layout: layout)
        #expect(decision == HoverDecision(mode: .collapsed, hitTestable: false, collapse: .cancel, hop: false))
    }

    @Test func enteringNotchExpandsAndHops() {
        let decision = HoverPolicy.react(to: onNotch, mode: .collapsed, layout: layout)
        #expect(decision == HoverDecision(mode: .expanded(.hover), hitTestable: true, collapse: .cancel, hop: true))
    }

    @Test func expandedPanelStaysWhileCursorIsInsideIt() {
        let decision = HoverPolicy.react(to: inExpandedOnly, mode: .expanded(.hover), layout: layout)
        #expect(decision.mode == .expanded(.hover))
        #expect(decision.hitTestable)
        #expect(decision.collapse == .cancel)
    }

    @Test func leavingExpandedPanelSchedulesCollapse() {
        let decision = HoverPolicy.react(to: CGPoint(x: 100, y: 100), mode: .expanded(.hover), layout: layout)
        #expect(decision.collapse == .schedule)
        #expect(!decision.hitTestable)
    }

    @Test func pinnedPanelIgnoresDistantCursorUntilVisited() {
        let away = HoverPolicy.react(to: CGPoint(x: 100, y: 100), mode: .expanded(.pinned), layout: layout)
        #expect(away.mode == .expanded(.pinned))
        #expect(away.collapse == .cancel)
        #expect(!away.hitTestable)
        let visited = HoverPolicy.react(to: inExpandedOnly, mode: .expanded(.pinned), layout: layout)
        #expect(visited.mode == .expanded(.hover))
        #expect(visited.hitTestable)
    }

    @Test func heldButtonFreezesTheModeButKeepsHitTestingCurrent() {
        let outside = CGPoint(x: 100, y: 100)
        #expect(HoverPolicy.react(to: outside, mode: .expanded(.hover), layout: layout, buttonHeld: true)
            == HoverDecision(mode: .expanded(.hover), hitTestable: false, collapse: .unchanged, hop: false))
        #expect(HoverPolicy.react(to: inExpandedOnly, mode: .expanded(.pinned), layout: layout, buttonHeld: true)
            == HoverDecision(mode: .expanded(.pinned), hitTestable: true, collapse: .unchanged, hop: false))
    }

    @Test func heldButtonOverTheNotchNeitherExpandsNorCatchesClicks() {
        let decision = HoverPolicy.react(to: onNotch, mode: .collapsed, layout: layout, buttonHeld: true)
        #expect(decision == HoverDecision(mode: .collapsed, hitTestable: false, collapse: .unchanged, hop: false))
    }
}

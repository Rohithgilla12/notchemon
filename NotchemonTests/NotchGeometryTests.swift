import CoreGraphics
import Testing
@testable import Notchemon

struct NotchGeometryTests {
    let macBookPro = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        safeAreaTop: 32,
        auxiliaryTopLeftWidth: 764,
        auxiliaryTopRightWidth: 764
    )
    let external = ScreenMetrics(
        frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
        safeAreaTop: 0,
        auxiliaryTopLeftWidth: 0,
        auxiliaryTopRightWidth: 0
    )

    @Test func hardwareNotchIsCentredGapBetweenAuxiliaryAreas() throws {
        let layout = try #require(NotchGeometry.layout(for: macBookPro, virtualNotchEnabled: false, wander: .topEdge))
        #expect(layout.kind == .hardware)
        #expect(layout.notch == CGRect(x: 764, y: 1085, width: 200, height: 32))
    }

    @Test func collapsedExtendsPeekBelowNotch() throws {
        let layout = try #require(NotchGeometry.layout(for: macBookPro, virtualNotchEnabled: false, wander: .topEdge))
        #expect(layout.collapsed == CGRect(x: 764, y: 1041, width: 200, height: 76))
    }

    @Test func fullScreenUsesSmallerPeek() throws {
        let layout = try #require(NotchGeometry.layout(for: macBookPro, virtualNotchEnabled: false, fullScreen: true, wander: .topEdge))
        #expect(layout.collapsed.height == 32 + NotchGeometry.fullScreenPeekHeight)
    }

    @Test func expandedIsCentredAndPinnedToTop() throws {
        let layout = try #require(NotchGeometry.layout(for: macBookPro, virtualNotchEnabled: false, wander: .topEdge))
        #expect(layout.expanded.midX == macBookPro.frame.midX)
        #expect(layout.expanded.maxY == macBookPro.frame.maxY)
        #expect(layout.expanded.width == 440)
        #expect(layout.expanded.height == CGFloat(212))
    }

    @Test func noNotchWithVirtualDisabledHasNoLayout() {
        #expect(NotchGeometry.layout(for: external, virtualNotchEnabled: false, wander: .topEdge) == nil)
    }

    @Test func noNotchWithVirtualEnabledDrawsVirtualNotchOnThatScreen() throws {
        let layout = try #require(NotchGeometry.layout(for: external, virtualNotchEnabled: true, wander: .topEdge))
        #expect(layout.kind == .virtual)
        #expect(layout.notch == CGRect(x: 1728 + 960 - 90, y: 1048, width: 180, height: 32))
    }

    @Test(arguments: [
        (WanderRange.off, CGFloat(1728), CGFloat(0)),
        (.nearNotch, 1728, 200),
        (.topEdge, 1728, 804),
        (.nearNotch, 400, 140),
        (.topEdge, 400, 140),
        (.topEdge, 100, 0),
    ])
    func reachIsClampedSoTheCreatureStaysOnItsScreen(wander: WanderRange, screenWidth: CGFloat, reach: CGFloat) {
        #expect(NotchGeometry.roamReach(wander, screenWidth: screenWidth) == reach)
    }

    @Test(arguments: [
        (WanderRange.off, CGRect(x: 644, y: 905, width: 440, height: 212)),
        (.nearNotch, CGRect(x: 604, y: 905, width: 520, height: 212)),
        (.topEdge, CGRect(x: 0, y: 905, width: 1728, height: 212)),
    ])
    func thePanelWidensToTheStripBelowTheMenuBarAndKeepsItsOpenAndClosedRects(wander: WanderRange, panel: CGRect) throws {
        let layout = try #require(NotchGeometry.layout(for: macBookPro, virtualNotchEnabled: false, wander: wander))
        #expect(layout.panel == panel)
        #expect(layout.panel.contains(layout.expanded))
        #expect(layout.collapsed == CGRect(x: 764, y: 1041, width: 200, height: 76))
        #expect(layout.expanded == CGRect(x: 644, y: 905, width: 440, height: 212))
    }

    @Test func aVirtualNotchOnASecondDisplayWandersOnlyAcrossThatDisplay() throws {
        let layout = try #require(NotchGeometry.layout(for: external, virtualNotchEnabled: true, wander: .topEdge))
        #expect(layout.roamReach == 900)
        #expect(layout.panel.minX == external.frame.minX)
        #expect(layout.panel.maxX == external.frame.maxX)
        #expect(layout.notch.midX - layout.roamReach - NotchGeometry.roamEdgeInset >= external.frame.minX)
        #expect(layout.notch.midX + layout.roamReach + NotchGeometry.roamEdgeInset <= external.frame.maxX)
    }

    @Test func fullScreenKeepsTheCreatureUnderTheNotch() throws {
        let layout = try #require(NotchGeometry.layout(for: macBookPro, virtualNotchEnabled: false, fullScreen: true, wander: .topEdge))
        #expect(layout.roamReach == 0)
        #expect(layout.panel == layout.expanded)
    }
}

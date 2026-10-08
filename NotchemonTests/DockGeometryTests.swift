import CoreGraphics
import Testing
@testable import Notchemon

struct DockGeometryTests {
    let macBookPro = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let external = CGRect(x: 1728, y: -200, width: 2560, height: 1440)
    /// The icon list this Mac's Dock reports at a 70 pt tile size, shown.
    let shownDock = CGRect(x: 120, y: 0, width: 1488, height: 90)

    func reading(_ frame: CGRect?, orientation: DockOrientation = .bottom, autoHides: Bool = false) -> DockReading {
        DockReading(listFrame: frame, orientation: orientation, autoHides: autoHides)
    }

    @Test func aVisibleBottomDockIsAShelfAlongItsTopInsetByHalfACreature() throws {
        let shelf = try #require(DockGeometry.shelf(reading(shownDock), screens: [macBookPro]))
        #expect(shelf.screen == macBookPro)
        #expect(shelf.top == 90)
        #expect(shelf.walkable == 142...1586)
        #expect(shelf.centreX == 864)
        #expect(shelf.range == -722...722)
    }

    @Test(arguments: [DockOrientation.left, .right])
    func aSideDockIsNoShelf(orientation: DockOrientation) {
        #expect(DockGeometry.shelf(reading(shownDock, orientation: orientation), screens: [macBookPro]) == nil)
    }

    @Test func anAutoHidingDockIsNoShelfEvenWhileShown() {
        #expect(DockGeometry.shelf(reading(shownDock, autoHides: true), screens: [macBookPro]) == nil)
    }

    @Test func anUnreadableDockIsNoShelf() {
        #expect(DockGeometry.shelf(reading(nil), screens: [macBookPro]) == nil)
    }

    @Test func aDockOffEveryScreenIsNoShelf() {
        let hidden = CGRect(x: 120, y: -90, width: 1488, height: 90)
        #expect(DockGeometry.shelf(reading(hidden), screens: [macBookPro]) == nil)
        #expect(DockGeometry.shelf(reading(shownDock), screens: []) == nil)
        let onUnpluggedDisplay = CGRect(x: 2000, y: -200, width: 1200, height: 90)
        #expect(DockGeometry.shelf(reading(onUnpluggedDisplay), screens: [macBookPro]) == nil)
    }

    @Test func aDockOnAnotherScreenIsAShelfOnThatScreen() throws {
        let dock = CGRect(x: 2500, y: -200, width: 1000, height: 80)
        let shelf = try #require(DockGeometry.shelf(reading(dock), screens: [macBookPro, external]))
        #expect(shelf.screen == external)
        #expect(shelf.top == -120)
        #expect(shelf.walkable == 2522...3478)
    }

    @Test(arguments: [(CGFloat(123), false), (124, true), (60, false)])
    func aDockTooNarrowToWalkIsNoShelf(width: CGFloat, isShelf: Bool) {
        let dock = CGRect(x: 864 - width / 2, y: 0, width: width, height: 60)
        let shelf = DockGeometry.shelf(reading(dock), screens: [macBookPro])
        #expect((shelf != nil) == isShelf)
        if let shelf { #expect(shelf.walkable.upperBound - shelf.walkable.lowerBound == DockGeometry.minimumWalk) }
    }

    @Test func theDockWindowSpansTheDockWithItsBottomOnTheTopEdgeAndTheCreatureCentredOnItsSpot() throws {
        let shelf = try #require(DockGeometry.shelf(reading(shownDock), screens: [macBookPro]))
        #expect(shelf.panel == CGRect(x: 120, y: 90, width: 1488, height: 88))
        #expect(shelf.spriteCentre(x: 0) == CGPoint(x: 864, y: 112))
        #expect(shelf.spriteCentre(x: -722) == CGPoint(x: 142, y: 112))
        #expect(shelf.panel.minX + DockGeometry.edgeInset == shelf.spriteCentre(x: shelf.range.lowerBound).x)
    }

    @Test func accessibilityFramesFlipIntoAppKitCoordinates() {
        #expect(DockGeometry.appKitFrame(axPosition: CGPoint(x: 120, y: 1027), size: CGSize(width: 1488, height: 90), primaryHeight: 1117) == shownDock)
        #expect(DockGeometry.appKitFrame(axPosition: CGPoint(x: 120, y: 1117), size: CGSize(width: 1488, height: 90), primaryHeight: 1117)
            == CGRect(x: 120, y: -90, width: 1488, height: 90))
    }
}

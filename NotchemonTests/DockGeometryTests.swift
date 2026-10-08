import CoreGraphics
import Testing
@testable import Notchemon

struct DockGeometryTests {
    let macBookPro = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let external = CGRect(x: 1728, y: -200, width: 2560, height: 1440)
    /// The icon list this Mac's Dock reports at a 70 pt tile size, shown.
    let shownDock = CGRect(x: 120, y: 0, width: 1488, height: 90)
    /// The same list as this Mac's auto-hiding Dock reports it while hidden, just below the screen.
    let hiddenDock = CGRect(x: 120, y: -90, width: 1488, height: 90)
    /// And once it has slid into view, measured: it stands 10 pt clear of the screen's bottom.
    let shownAutoHidingDock = CGRect(x: 120, y: 10, width: 1488, height: 90)

    func reading(_ frame: CGRect?, orientation: DockOrientation = .bottom, autoHides: Bool = false) -> DockReading {
        DockReading(listFrame: frame, orientation: orientation, autoHides: autoHides)
    }

    @Test func aVisibleBottomDockIsAShelfAlongItsTopInsetByHalfACreature() throws {
        let shelf = try #require(DockGeometry.shelf(reading(shownDock), screens: [macBookPro]))
        #expect(shelf.screen == macBookPro)
        #expect(shelf.ground == 90)
        #expect(shelf.autoHide == nil)
        #expect(shelf.step == nil)
        #expect(shelf.walkable == 142...1586)
        #expect(shelf.centreX == 864)
        #expect(shelf.range == -722...722)
    }

    @Test(arguments: [(DockOrientation.left, false), (.right, false), (.left, true), (.right, true)])
    func aSideDockIsNoShelf(orientation: DockOrientation, autoHides: Bool) {
        #expect(DockGeometry.shelf(reading(shownDock, orientation: orientation, autoHides: autoHides), screens: [macBookPro]) == nil)
        #expect(DockGeometry.shelf(reading(hiddenDock, orientation: orientation, autoHides: autoHides), screens: [macBookPro]) == nil)
    }

    @Test func aHiddenAutoHidingDockIsAWalkAlongTheScreensBottomEdgeInsetByHalfACreatureAndAMargin() throws {
        let shelf = try #require(DockGeometry.shelf(reading(hiddenDock, autoHides: true), screens: [macBookPro]))
        #expect(shelf.screen == macBookPro)
        #expect(shelf.ground == 0)
        #expect(shelf.walkable == 30...1698)
        #expect(shelf.range == -834...834)
        #expect(shelf.autoHide == AutoHidingDock(span: 120...1608, top: 100, height: 90, slide: .hidden))
        #expect(shelf.step == nil)
        #expect(shelf.spriteCentre(x: 0) == CGPoint(x: 864, y: 22))
        #expect(shelf.spriteCentre(x: -834) == CGPoint(x: 30, y: 22))
    }

    @Test func aShownAutoHidingDockRaisesTheGroundToItsTopOnlyOverItsSpan() throws {
        let shelf = try #require(DockGeometry.shelf(reading(shownAutoHidingDock, autoHides: true), screens: [macBookPro]))
        #expect(shelf.ground == 0)
        #expect(shelf.walkable == 30...1698)
        #expect(shelf.autoHide == AutoHidingDock(span: 120...1608, top: 100, height: 90, slide: .shown))
        #expect(shelf.step == GroundStep(span: -744...744, height: 100))
        #expect(shelf.spriteCentre(x: 0) == CGPoint(x: 864, y: 122))
        #expect(shelf.spriteCentre(x: -744) == CGPoint(x: 120, y: 122))
        #expect(shelf.spriteCentre(x: 744) == CGPoint(x: 1608, y: 122))
        #expect(shelf.spriteCentre(x: -745) == CGPoint(x: 119, y: 22))
        #expect(shelf.spriteCentre(x: 834) == CGPoint(x: 1698, y: 22))
    }

    @Test(arguments: [(CGFloat(-90), AutoHidingDock.Slide.hidden), (-89, .sliding), (-1, .sliding), (0, .shown)])
    func aDockReadPartWayInIsSlidingAndRaisesNothing(y: CGFloat, slide: AutoHidingDock.Slide) throws {
        let moving = CGRect(x: 120, y: y, width: 1488, height: 90)
        let shelf = try #require(DockGeometry.shelf(reading(moving, autoHides: true), screens: [macBookPro]))
        #expect(shelf.autoHide?.slide == slide)
        #expect((shelf.step != nil) == (slide == .shown))
    }

    @Test(arguments: [CGFloat(10), 4, 0])
    func anAutoHidingDockKeepsOneWindowWhetherShownOrHidden(gap: CGFloat) throws {
        let hidden = try #require(DockGeometry.shelf(reading(hiddenDock, autoHides: true), screens: [macBookPro]))
        let shownFrame = CGRect(x: 120, y: gap, width: 1488, height: 90)
        let shown = try #require(DockGeometry.shelf(reading(shownFrame, autoHides: true), screens: [macBookPro]))
        #expect(hidden.panel == CGRect(x: 8, y: 0, width: 1712, height: 188))
        #expect(shown.panel == hidden.panel)
        #expect(shown.panel.maxY >= shownFrame.maxY + 2 * DockShelf.spriteSide)
        #expect(shown.range == hidden.range)
        #expect(hidden.panel(keeping: shown.panel) == hidden.panel)
    }

    @Test func aDockShownHigherThanEstimatedGrowsTheWindowOnceAndKeepsIt() throws {
        let hidden = try #require(DockGeometry.shelf(reading(hiddenDock, autoHides: true), screens: [macBookPro]))
        let shown = try #require(DockGeometry.shelf(reading(CGRect(x: 120, y: 16, width: 1488, height: 90), autoHides: true), screens: [macBookPro]))
        let grown = shown.panel(keeping: hidden.panel)
        #expect(grown == CGRect(x: 8, y: 0, width: 1712, height: 194))
        #expect(hidden.panel(keeping: grown) == grown)
        #expect(shown.panel(keeping: grown) == grown)
    }

    @Test func aWindowForAnotherSpanOrScreenIsNotKept() throws {
        let hidden = try #require(DockGeometry.shelf(reading(hiddenDock, autoHides: true), screens: [macBookPro]))
        let elsewhere = CGRect(x: 1758, y: -200, width: 2530, height: 400)
        #expect(hidden.panel(keeping: elsewhere) == hidden.panel)
        #expect(hidden.panel(keeping: .zero) == hidden.panel)
    }

    @Test func aHiddenDockBelowAnotherScreenWalksAlongThatScreensBottom() throws {
        let dock = CGRect(x: 2500, y: -290, width: 1000, height: 90)
        let shelf = try #require(DockGeometry.shelf(reading(dock, autoHides: true), screens: [macBookPro, external]))
        #expect(shelf.screen == external)
        #expect(shelf.ground == -200)
        #expect(shelf.walkable == 1758...4258)
        #expect(shelf.autoHide == AutoHidingDock(span: 2500...3500, top: -100, height: 90, slide: .hidden))
    }

    @Test func aDockUnderAFullScreenAppIsNoShelfWhicheverScreenTheNotchIsOn() {
        let dock = CGRect(x: 2500, y: -290, width: 1000, height: 90)
        let onExternal = reading(dock, autoHides: true)
        #expect(DockGeometry.shelf(onExternal, screens: [macBookPro, external], isFullScreen: { $0 == external }) == nil)
        let besideAFullScreenNotch = DockGeometry.shelf(onExternal, screens: [macBookPro, external], isFullScreen: { $0 == macBookPro })
        #expect(besideAFullScreenNotch?.screen == external)
        #expect(DockGeometry.shelf(reading(shownDock), screens: [macBookPro, external], isFullScreen: { $0 == macBookPro }) == nil)
        #expect(DockGeometry.shelf(reading(shownDock), screens: [macBookPro, external], isFullScreen: { $0 == external }) != nil)
    }

    @Test func anAutoHidingDockFarFromEveryScreensBottomIsNoShelf() {
        let farBelow = CGRect(x: 120, y: -400, width: 1488, height: 90)
        #expect(DockGeometry.shelf(reading(farBelow, autoHides: true), screens: [macBookPro]) == nil)
        let farAbove = CGRect(x: 120, y: 91, width: 1488, height: 90)
        #expect(DockGeometry.shelf(reading(farAbove, autoHides: true), screens: [macBookPro]) == nil)
        #expect(DockGeometry.shelf(reading(hiddenDock, autoHides: true), screens: []) == nil)
        #expect(DockGeometry.shelf(reading(nil, autoHides: true), screens: [macBookPro]) == nil)
    }

    @Test func anUnreadableDockIsNoShelf() {
        #expect(DockGeometry.shelf(reading(nil), screens: [macBookPro]) == nil)
    }

    @Test func aDockOffEveryScreenIsNoShelf() {
        #expect(DockGeometry.shelf(reading(hiddenDock), screens: [macBookPro]) == nil)
        #expect(DockGeometry.shelf(reading(shownDock), screens: []) == nil)
        let onUnpluggedDisplay = CGRect(x: 2000, y: -200, width: 1200, height: 90)
        #expect(DockGeometry.shelf(reading(onUnpluggedDisplay), screens: [macBookPro]) == nil)
    }

    @Test func aDockOnAnotherScreenIsAShelfOnThatScreen() throws {
        let dock = CGRect(x: 2500, y: -200, width: 1000, height: 80)
        let shelf = try #require(DockGeometry.shelf(reading(dock), screens: [macBookPro, external]))
        #expect(shelf.screen == external)
        #expect(shelf.ground == -120)
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

    @Test func theCursorCallsForTheDockAtTheBottomEdgeAndOverTheShownDockOnly() throws {
        let hidden = try #require(DockGeometry.shelf(reading(hiddenDock, autoHides: true), screens: [macBookPro]))
        let shown = try #require(DockGeometry.shelf(reading(shownAutoHidingDock, autoHides: true), screens: [macBookPro]))
        #expect(DockGeometry.shelf(reading(shownDock), screens: [macBookPro])?.cursorShowsDock(CGPoint(x: 600, y: 0)) == nil)
        #expect(hidden.cursorShowsDock(CGPoint(x: 5, y: 2)) == true)
        #expect(hidden.cursorShowsDock(CGPoint(x: 600, y: 4)) == false)
        #expect(hidden.cursorShowsDock(CGPoint(x: 600, y: 50)) == false)
        #expect(hidden.cursorShowsDock(CGPoint(x: 2000, y: 0)) == false)
        #expect(shown.cursorShowsDock(CGPoint(x: 600, y: 50)) == true)
        #expect(shown.cursorShowsDock(CGPoint(x: 600, y: 100)) == true)
        #expect(shown.cursorShowsDock(CGPoint(x: 600, y: 101)) == false)
        #expect(shown.cursorShowsDock(CGPoint(x: 60, y: 50)) == false)
        #expect(shown.cursorShowsDock(CGPoint(x: 60, y: 1)) == true)
    }
}

extension DockGeometryTests {
    @Test func aReadSaysWhyThereIsNoShelf() {
        #expect(DockGeometry.read(reading(nil), screens: [macBookPro]) == .unreadable)
        #expect(DockGeometry.read(reading(shownDock, orientation: .left), screens: [macBookPro]) == .noShelf(.sideDock))
        #expect(DockGeometry.read(reading(shownDock), screens: []) == .noShelf(.noRoom))
        let narrow = CGRect(x: 800, y: 0, width: 100, height: 90)
        #expect(DockGeometry.read(reading(narrow), screens: [macBookPro]) == .noShelf(.noRoom))
        #expect(DockGeometry.read(reading(shownDock), screens: [macBookPro], isFullScreen: { _ in true }) == .noShelf(.fullScreen))
        #expect(DockGeometry.read(reading(shownDock), screens: [macBookPro]).shelf?.ground == 90)
    }
}

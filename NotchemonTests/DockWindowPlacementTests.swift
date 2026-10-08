import CoreGraphics
import Testing
@testable import Notchemon

struct DockWindowPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    var shelf: DockShelf {
        DockGeometry.shelf(DockReading(listFrame: CGRect(x: 120, y: 0, width: 1488, height: 90), orientation: .bottom, autoHides: false), screens: [screen])!
    }

    @Test func aDockThatGoesWhileTheCreatureIsOnItKeepsItsWindowUntilTheCreatureHasLeft() {
        var placement = DockWindowPlacement()
        let shown = placement.frame(for: shelf, creatureThere: true, current: .zero)
        #expect(shown == shelf.panel)
        #expect(placement.frame(for: nil, creatureThere: true, current: shelf.panel) == shelf.panel)
        #expect(placement.frame(for: nil, creatureThere: false, current: shelf.panel) == nil)
        #expect(placement.frame(for: nil, creatureThere: true, current: shelf.panel) == nil)
    }

    @Test func theWindowIsHiddenWhileTheCreatureIsElsewhere() {
        var placement = DockWindowPlacement()
        #expect(placement.frame(for: shelf, creatureThere: false, current: .zero) == nil)
        #expect(placement.frame(for: nil, creatureThere: true, current: .zero) == nil)
    }
}

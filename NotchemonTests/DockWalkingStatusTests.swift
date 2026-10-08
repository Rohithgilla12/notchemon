import CoreGraphics
import Testing
@testable import Notchemon

struct DockWalkingStatusTests {
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    func shelf(_ y: CGFloat, autoHides: Bool) -> DockShelf {
        DockGeometry.shelf(DockReading(listFrame: CGRect(x: 120, y: y, width: 1488, height: 90), orientation: .bottom, autoHides: autoHides), screens: [screen])!
    }

    func line(wanted: Bool = true, trusted: Bool = true, _ read: DockRead?) -> String {
        DockWalkingStatus.line(wanted: wanted, trusted: trusted, read: read)
    }

    @Test func wantedComesBeforeTrustAndTrustBeforeTheRead() {
        #expect(line(wanted: false, trusted: false, nil) == "Dock walking: off")
        #expect(line(wanted: false, .shelf(shelf(0, autoHides: false))) == "Dock walking: off")
        #expect(line(trusted: false, nil) == "Dock walking: needs Accessibility")
        #expect(line(trusted: false, .shelf(shelf(0, autoHides: false))) == "Dock walking: needs Accessibility")
    }

    @Test func eachReadHasItsOwnLine() {
        #expect(line(nil) == "Dock walking: reading the Dock")
        #expect(line(.unreadable) == "Dock walking: Dock did not answer")
        #expect(line(.noShelf(.sideDock)) == "Dock walking: Dock is on the side")
        #expect(line(.noShelf(.noRoom)) == "Dock walking: Dock too small to walk")
        #expect(line(.noShelf(.fullScreen)) == "Dock walking: off in full screen")
        #expect(line(.shelf(shelf(0, autoHides: false))) == "Dock walking: on")
        #expect(line(.shelf(shelf(10, autoHides: true))) == "Dock walking: on")
        #expect(line(.shelf(shelf(-90, autoHides: true))) == "Dock walking: on (Dock hidden, walking the bottom edge)")
    }
}

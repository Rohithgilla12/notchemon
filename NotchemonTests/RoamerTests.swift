import Foundation
import Testing
@testable import Notchemon

@MainActor
struct RoamerTests {
    let range: ClosedRange<Double> = -800...800

    @Test func anUpdateFromInsideANotificationLandsAndTheOuterOneSeesItsResult() {
        let roamer = Roamer()
        var seen: [RoamPhase] = []
        var afterNested: RoamPhase?
        roamer.onLookAgain = {
            seen.append(roamer.phase)
            guard seen.count == 1 else { return }
            roamer.update(range: range, homing: .walk)
            afterNested = roamer.phase
        }

        roamer.update(range: range, homing: .free)

        guard case .resting(at: 0, _) = seen.first else {
            Issue.record("leaving home rests there first, saw \(seen)")
            return
        }
        #expect(seen.count == 2)
        #expect(seen.last == .home)
        #expect(afterNested == .home)
        #expect(roamer.phase == .home)
    }
}

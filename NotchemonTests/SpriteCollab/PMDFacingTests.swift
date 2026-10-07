import Testing
@testable import Notchemon

struct PMDFacingTests {
    @Test(arguments: [
        (0.0, -10.0, PMDFacing.down),
        (10, -10, .downRight),
        (10, 0, .right),
        (10, 10, .upRight),
        (0, 10, .up),
        (-10, 10, .upLeft),
        (-10, 0, .left),
        (-10, -10, .downLeft),
    ])
    func mapsEachOctant(dx: Double, dy: Double, expected: PMDFacing) {
        #expect(PMDFacing.toward(dx: dx, dy: dy) == expected)
    }

    @Test func snapsToNearestDirection() {
        #expect(PMDFacing.toward(dx: 100, dy: -30) == .right)
        #expect(PMDFacing.toward(dx: 30, dy: -100) == .down)
        #expect(PMDFacing.toward(dx: -100, dy: 30) == .left)
        #expect(PMDFacing.toward(dx: -60, dy: -50) == .downLeft)
    }

    @Test func nearZeroVectorFacesDown() {
        #expect(PMDFacing.toward(dx: 0, dy: 0) == .down)
        #expect(PMDFacing.toward(dx: -0.1, dy: 0.2) == .down)
    }

    @Test func rowOrderMatchesSheetLayout() {
        #expect(PMDFacing.allCases == [.down, .downRight, .right, .upRight, .up, .upLeft, .left, .downLeft])
        #expect(PMDFacing.allCases.map(\.rawValue) == Array(0..<8))
    }
}

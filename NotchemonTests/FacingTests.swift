import Testing
@testable import Notchemon

struct FacingTests {
    @Test(arguments: [
        (0.0, -10.0, Facing.down),
        (10, -10, .downRight),
        (10, 0, .right),
        (10, 10, .upRight),
        (0, 10, .up),
        (-10, 10, .upLeft),
        (-10, 0, .left),
        (-10, -10, .downLeft),
    ])
    func mapsEachOctant(dx: Double, dy: Double, expected: Facing) {
        #expect(Facing.toward(dx: dx, dy: dy) == expected)
    }

    @Test func snapsToNearestDirection() {
        #expect(Facing.toward(dx: 100, dy: -30) == .right)
        #expect(Facing.toward(dx: 30, dy: -100) == .down)
        #expect(Facing.toward(dx: -100, dy: 30) == .left)
        #expect(Facing.toward(dx: -60, dy: -50) == .downLeft)
    }

    @Test func nearZeroVectorFacesDown() {
        #expect(Facing.toward(dx: 0, dy: 0) == .down)
        #expect(Facing.toward(dx: -0.1, dy: 0.2) == .down)
    }

    @Test func rowOrderMatchesSheetLayout() {
        #expect(Facing.allCases == [.down, .downRight, .right, .upRight, .up, .upLeft, .left, .downLeft])
        #expect(Facing.allCases.map(\.rawValue) == Array(0..<8))
    }
}

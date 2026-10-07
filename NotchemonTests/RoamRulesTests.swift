import Foundation
import Testing
@testable import Notchemon

/// SplitMix64, so each seed replays the same wander.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct RoamRulesTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let range: ClosedRange<Double> = -800...800

    func inputs(at seconds: TimeInterval = 0, homing: Homing = .free, range: ClosedRange<Double>? = nil) -> RoamInputs {
        RoamInputs(now: t0 + seconds, range: range ?? self.range, homing: homing)
    }

    @Test(arguments: 0..<50)
    func leavingHomeFirstRestsFourToFifteenSeconds(seed: UInt64) throws {
        var rng = SeededRandom(state: seed)
        guard case .resting(let x, let until) = RoamRules.next(.home, inputs(), using: &rng) else {
            Issue.record("expected a rest")
            return
        }
        #expect(x == 0)
        #expect((4...15).contains(until.timeIntervalSince(t0)))
    }

    @Test(arguments: 0..<200)
    func aFinishedRestWalksAtLeastSixtyPointsWithinRangeAtWalkingPace(seed: UInt64) throws {
        var rng = SeededRandom(state: seed)
        let start = Double(seed % 9) * 100 - 400
        let next = RoamRules.next(.resting(at: start, until: t0), inputs(), using: &rng)
        let walk = try #require(next.walk)
        guard case .walking = next else {
            Issue.record("a rest ends in a walk to the next spot")
            return
        }
        #expect(walk.from == start)
        #expect(walk.start == t0)
        #expect(range.contains(walk.to))
        #expect(abs(walk.to - start) >= RoamRules.minimumStride)
        #expect(walk.speed == 35)
        #expect(abs(walk.duration - abs(walk.to - start) / 35) < 1e-9)
    }

    @Test func someWalksFromAwayHeadHome() {
        let targets = (0..<200).compactMap { seed -> Double? in
            var rng = SeededRandom(state: UInt64(seed))
            return RoamRules.next(.resting(at: 300, until: t0), inputs(), using: &rng).walk?.to
        }
        let home = targets.filter { $0 == 0 }.count
        #expect(targets.count == 200)
        #expect((20...80).contains(home))
    }

    @Test func aRestNotYetOverIsLeftAlone() {
        var rng = SeededRandom(state: 1)
        let resting = RoamPhase.resting(at: 120, until: t0 + 5)
        #expect(RoamRules.next(resting, inputs(at: 4.9), using: &rng) == resting)
    }

    @Test func aRangeTooNarrowForAStrideRestsAgainWhereItIs() {
        var rng = SeededRandom(state: 3)
        let next = RoamRules.next(.resting(at: 0, until: t0), inputs(range: -50...50), using: &rng)
        guard case .resting(let x, let until) = next else {
            Issue.record("expected another rest")
            return
        }
        #expect(x == 0)
        #expect(until > t0)
    }

    @Test func theCurrentXFollowsTheWalkAtAnyInstant() {
        let walk = RoamWalk(from: -70, to: 70, start: t0, speed: 35)
        let phase = RoamPhase.walking(walk)
        #expect(walk.duration == 4)
        #expect(walk.direction == .right)
        #expect(phase.x(at: t0 - 1) == -70)
        #expect(phase.x(at: t0 + 1) == -35)
        #expect(phase.x(at: t0 + 2) == 0)
        #expect(phase.x(at: t0 + 9) == 70)
        #expect(RoamWalk(from: 70, to: 0, start: t0, speed: 35).direction == .left)
        #expect(RoamPhase.resting(at: 42, until: t0).x(at: t0 + 100) == 42)
        #expect(RoamPhase.home.x(at: t0) == 0)
    }

    @Test func aWalkInProgressIsLeftAloneAndRestsAtItsEnd() throws {
        var rng = SeededRandom(state: 5)
        let walking = RoamPhase.walking(RoamWalk(from: 0, to: 140, start: t0, speed: 35))
        #expect(RoamRules.next(walking, inputs(at: 3.9), using: &rng) == walking)
        guard case .resting(let x, let until) = RoamRules.next(walking, inputs(at: 4), using: &rng) else {
            Issue.record("a finished walk rests")
            return
        }
        #expect(x == 140)
        #expect((4...15).contains(until.timeIntervalSince(t0 + 4)))
    }

    @Test(arguments: [
        RoamPhase.home,
        .resting(at: 300, until: .distantFuture),
        .walking(RoamWalk(from: 0, to: 300, start: Date(timeIntervalSince1970: 1_800_000_000), speed: 35)),
        .returning(RoamWalk(from: 300, to: 0, start: Date(timeIntervalSince1970: 1_800_000_000), speed: 70)),
    ])
    func snappingHomeIsImmediate(phase: RoamPhase) {
        var rng = SeededRandom(state: 7)
        #expect(RoamRules.next(phase, inputs(at: 1, homing: .snap), using: &rng) == .home)
    }

    @Test func walkingHomeStartsFromWhereverTheCreatureIsAndStaysHome() {
        var rng = SeededRandom(state: 9)
        let walking = RoamPhase.walking(RoamWalk(from: 0, to: 140, start: t0, speed: 35))
        let returning = RoamRules.next(walking, inputs(at: 2, homing: .walk), using: &rng)
        #expect(returning == .returning(RoamWalk(from: 70, to: 0, start: t0 + 2, speed: 35)))
        #expect(RoamRules.next(returning, inputs(at: 3, homing: .walk), using: &rng) == returning)
        #expect(RoamRules.next(returning, inputs(at: 4, homing: .walk), using: &rng) == .home)
        #expect(RoamRules.next(.home, inputs(at: 60, homing: .walk), using: &rng) == .home)
    }

    @Test func greetingTheCursorRunsHomeAtTwiceThePaceFromMidWalk() {
        var rng = SeededRandom(state: 11)
        let returning = RoamPhase.returning(RoamWalk(from: 140, to: 0, start: t0, speed: RoamRules.walkSpeed))
        let running = RoamRules.next(returning, inputs(at: 2, homing: .run), using: &rng)
        #expect(running == .returning(RoamWalk(from: 70, to: 0, start: t0 + 2, speed: 70)))
        #expect(RoamRules.runSpeed == 2 * RoamRules.walkSpeed)
        #expect(RoamRules.next(running, inputs(at: 2.5, homing: .run), using: &rng) == running)
        #expect(RoamRules.next(running, inputs(at: 3, homing: .run), using: &rng) == .home)
    }

    @Test func aCreatureAlreadyHomeWhenCalledIsHome() {
        var rng = SeededRandom(state: 13)
        #expect(RoamRules.next(.resting(at: 0, until: .distantFuture), inputs(homing: .run), using: &rng) == .home)
    }

    @Test func freedMidReturnItFinishesTheSameWalkAndRestsAtHome() throws {
        var rng = SeededRandom(state: 15)
        let walk = RoamWalk(from: 140, to: 0, start: t0, speed: 35)
        #expect(RoamRules.next(.returning(walk), inputs(at: 1), using: &rng) == .walking(walk))
        guard case .resting(let x, _) = RoamRules.next(.returning(walk), inputs(at: 4), using: &rng) else {
            Issue.record("expected a rest at home")
            return
        }
        #expect(x == 0)
    }

    @Test func aScreenThatShrinksPullsTheCreatureBackInside() {
        var rng = SeededRandom(state: 17)
        let narrow: ClosedRange<Double> = -200...200
        let rest = RoamRules.next(.resting(at: 600, until: t0 + 5), inputs(range: narrow), using: &rng)
        #expect(rest == .resting(at: 200, until: t0 + 5))
        let walk = RoamPhase.walking(RoamWalk(from: 100, to: 700, start: t0, speed: 35))
        guard case .resting(let x, _) = RoamRules.next(walk, inputs(at: 2, range: narrow), using: &rng) else {
            Issue.record("expected a rest inside the new range")
            return
        }
        #expect(x == 170)
    }

    @Test func deadlinesAreWhenEachPhaseEndsByItself() {
        #expect(RoamPhase.home.deadline == nil)
        #expect(RoamPhase.resting(at: 1, until: t0 + 6).deadline == t0 + 6)
        #expect(RoamPhase.walking(RoamWalk(from: 0, to: 70, start: t0, speed: 35)).deadline == t0 + 2)
    }
}

struct HomingTests {
    static let free = HomingConditions(
        wander: .topEdge, panelOpen: false, sleeping: false, focusing: false, fullScreen: false, cursorNearHome: false, hasCreature: true
    )

    static func with(_ change: (inout HomingConditions) -> Void) -> HomingConditions {
        var conditions = free
        change(&conditions)
        return conditions
    }

    @Test(arguments: [
        (free, Homing.free),
        (with { $0.wander = .nearNotch }, .free),
        (with { $0.wander = .off }, .walk),
        (with { $0.sleeping = true }, .walk),
        (with { $0.focusing = true }, .walk),
        (with { $0.cursorNearHome = true }, .run),
        (with { $0.cursorNearHome = true; $0.sleeping = true }, .run),
        (with { $0.panelOpen = true }, .snap),
        (with { $0.fullScreen = true }, .snap),
        (with { $0.hasCreature = false }, .snap),
        (with { $0.panelOpen = true; $0.cursorNearHome = true }, .snap),
        (with { $0.fullScreen = true; $0.wander = .off }, .snap),
    ])
    func eachConditionCallsTheCreatureHome(conditions: HomingConditions, expected: Homing) {
        #expect(RoamRules.homing(conditions) == expected)
    }
}

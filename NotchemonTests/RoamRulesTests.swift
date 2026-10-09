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
        guard case .resting(let spot, let until) = RoamRules.next(.home, inputs(), using: &rng) else {
            Issue.record("expected a rest")
            return
        }
        #expect(spot == .topEdge(0))
        #expect((4...15).contains(until.timeIntervalSince(t0)))
    }

    @Test(arguments: 0..<200)
    func aFinishedRestWalksAtLeastSixtyPointsWithinRangeAtWalkingPace(seed: UInt64) throws {
        var rng = SeededRandom(state: seed)
        let start = Double(seed % 9) * 100 - 400
        let next = RoamRules.next(.resting(at: .topEdge(start), until: t0), inputs(), using: &rng)
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
            return RoamRules.next(.resting(at: .topEdge(300), until: t0), inputs(), using: &rng).walk?.to
        }
        let home = targets.filter { $0 == 0 }.count
        #expect(targets.count == 200)
        #expect((20...80).contains(home))
    }

    @Test func aRestNotYetOverIsLeftAlone() {
        var rng = SeededRandom(state: 1)
        let resting = RoamPhase.resting(at: .topEdge(120), until: t0 + 5)
        #expect(RoamRules.next(resting, inputs(at: 4.9), using: &rng) == resting)
    }

    @Test func aRangeTooNarrowForAStrideRestsAgainWhereItIs() {
        var rng = SeededRandom(state: 3)
        let next = RoamRules.next(.resting(at: .topEdge(0), until: t0), inputs(range: -50...50), using: &rng)
        guard case .resting(let spot, let until) = next else {
            Issue.record("expected another rest")
            return
        }
        #expect(spot == .topEdge(0))
        #expect(until > t0)
    }

    @Test func theCurrentXFollowsTheWalkAtAnyInstant() {
        let walk = RoamWalk(on: .topEdge, from: -70, to: 70, start: t0, speed: 35)
        let phase = RoamPhase.walking(walk)
        #expect(walk.duration == 4)
        #expect(walk.direction == .right)
        #expect(phase.spot(at: t0 - 1) == .topEdge(-70))
        #expect(phase.spot(at: t0 + 1) == .topEdge(-35))
        #expect(phase.spot(at: t0 + 2) == .topEdge(0))
        #expect(phase.spot(at: t0 + 9) == .topEdge(70))
        #expect(RoamWalk(on: .topEdge, from: 70, to: 0, start: t0, speed: 35).direction == .left)
        #expect(RoamPhase.resting(at: .topEdge(42), until: t0).spot(at: t0 + 100) == .topEdge(42))
        #expect(RoamPhase.home.spot(at: t0) == .home)
    }

    @Test func aWalkInProgressIsLeftAloneAndRestsAtItsEnd() throws {
        var rng = SeededRandom(state: 5)
        let walking = RoamPhase.walking(RoamWalk(on: .topEdge, from: 0, to: 140, start: t0, speed: 35))
        #expect(RoamRules.next(walking, inputs(at: 3.9), using: &rng) == walking)
        guard case .resting(let spot, let until) = RoamRules.next(walking, inputs(at: 4), using: &rng) else {
            Issue.record("a finished walk rests")
            return
        }
        #expect(spot == .topEdge(140))
        #expect((4...15).contains(until.timeIntervalSince(t0 + 4)))
    }

    @Test(arguments: [
        RoamPhase.home,
        .resting(at: .topEdge(300), until: .distantFuture),
        .walking(RoamWalk(on: .topEdge, from: 0, to: 300, start: Date(timeIntervalSince1970: 1_800_000_000), speed: 35)),
        .returning(RoamWalk(on: .topEdge, from: 300, to: 0, start: Date(timeIntervalSince1970: 1_800_000_000), speed: 70)),
        .stopped(at: .topEdge(-300)),
    ])
    func snappingHomeIsImmediate(phase: RoamPhase) {
        var rng = SeededRandom(state: 7)
        #expect(RoamRules.next(phase, inputs(at: 1, homing: .snap), using: &rng) == .home)
    }

    @Test func walkingHomeStartsFromWhereverTheCreatureIsAndStaysHome() {
        var rng = SeededRandom(state: 9)
        let walking = RoamPhase.walking(RoamWalk(on: .topEdge, from: 0, to: 140, start: t0, speed: 35))
        let returning = RoamRules.next(walking, inputs(at: 2, homing: .walk), using: &rng)
        #expect(returning == .returning(RoamWalk(on: .topEdge, from: 70, to: 0, start: t0 + 2, speed: 35)))
        #expect(RoamRules.next(returning, inputs(at: 3, homing: .walk), using: &rng) == returning)
        #expect(RoamRules.next(returning, inputs(at: 4, homing: .walk), using: &rng) == .home)
        #expect(RoamRules.next(.home, inputs(at: 60, homing: .walk), using: &rng) == .home)
    }

    @Test func greetingTheCursorRunsHomeAtTwiceThePaceFromMidWalk() {
        var rng = SeededRandom(state: 11)
        let returning = RoamPhase.returning(RoamWalk(on: .topEdge, from: 140, to: 0, start: t0, speed: RoamRules.walkSpeed))
        let running = RoamRules.next(returning, inputs(at: 2, homing: .run), using: &rng)
        #expect(running == .returning(RoamWalk(on: .topEdge, from: 70, to: 0, start: t0 + 2, speed: 70)))
        #expect(RoamRules.runSpeed == 2 * RoamRules.walkSpeed)
        #expect(RoamRules.next(running, inputs(at: 2.5, homing: .run), using: &rng) == running)
        #expect(RoamRules.next(running, inputs(at: 3, homing: .run), using: &rng) == .home)
    }

    @Test func aCreatureAlreadyHomeWhenCalledIsHome() {
        var rng = SeededRandom(state: 13)
        #expect(RoamRules.next(.resting(at: .topEdge(0), until: .distantFuture), inputs(homing: .run), using: &rng) == .home)
    }

    @Test func freedMidReturnItFinishesTheSameWalkAndRestsAtHome() throws {
        var rng = SeededRandom(state: 15)
        let walk = RoamWalk(on: .topEdge, from: 140, to: 0, start: t0, speed: 35)
        #expect(RoamRules.next(.returning(walk), inputs(at: 1), using: &rng) == .walking(walk))
        guard case .resting(let spot, _) = RoamRules.next(.returning(walk), inputs(at: 4), using: &rng) else {
            Issue.record("expected a rest at home")
            return
        }
        #expect(spot == .topEdge(0))
    }

    @Test func aRangeThatShrinksPastTheCreatureWalksItBackToTheNearestEdge() throws {
        var rng = SeededRandom(state: 17)
        let narrow: ClosedRange<Double> = -200...200
        #expect(RoamRules.next(.resting(at: .topEdge(600), until: t0 + 5), inputs(range: narrow), using: &rng)
            == .walking(RoamWalk(on: .topEdge, from: 600, to: 200, start: t0, speed: RoamRules.walkSpeed)))
        #expect(RoamRules.next(.resting(at: .topEdge(-600), until: t0 + 5), inputs(range: narrow), using: &rng)
            == .walking(RoamWalk(on: .topEdge, from: -600, to: -200, start: t0, speed: RoamRules.walkSpeed)))

        let outbound = RoamPhase.walking(RoamWalk(on: .topEdge, from: 100, to: 660, start: t0, speed: RoamRules.walkSpeed))
        let back = RoamRules.next(outbound, inputs(at: 8, range: narrow), using: &rng)
        let walk = try #require(back.walk)
        #expect(back == .walking(RoamWalk(on: .topEdge, from: 380, to: 200, start: t0 + 8, speed: RoamRules.walkSpeed)))
        let arrival = walk.end.timeIntervalSince(t0)
        #expect(RoamRules.next(back, inputs(at: arrival - 0.1, range: narrow), using: &rng) == back)
        guard case .resting(let spot, _) = RoamRules.next(back, inputs(at: arrival, range: narrow), using: &rng) else {
            Issue.record("the walk back rests at the edge it reached")
            return
        }
        #expect(spot == .topEdge(200))
    }

    @Test func aWalkWhoseTargetLeavesTheRangeStopsWhereItIsWhenThatIsStillInside() {
        var rng = SeededRandom(state: 19)
        let walk = RoamPhase.walking(RoamWalk(on: .topEdge, from: 100, to: 700, start: t0, speed: 35))
        guard case .resting(let spot, _) = RoamRules.next(walk, inputs(at: 2, range: -200...200), using: &rng) else {
            Issue.record("expected a rest where it stood")
            return
        }
        #expect(spot == .topEdge(170))
    }

    @Test func farthestIsTheMostAPhaseTakesTheCreatureFromHome() {
        #expect(RoamPhase.home.farthestAlongTopEdge == 0)
        #expect(RoamPhase.resting(at: .topEdge(-420), until: t0).farthestAlongTopEdge == 420)
        #expect(RoamPhase.walking(RoamWalk(on: .topEdge, from: 600, to: 200, start: t0, speed: 35)).farthestAlongTopEdge == 600)
        #expect(RoamPhase.walking(RoamWalk(on: .topEdge, from: -100, to: -500, start: t0, speed: 35)).farthestAlongTopEdge == 500)
        #expect(RoamPhase.returning(RoamWalk(on: .topEdge, from: 300, to: 0, start: t0, speed: 70)).farthestAlongTopEdge == 300)
        #expect(RoamPhase.stopped(at: .topEdge(-250)).farthestAlongTopEdge == 250)
    }

    @Test func fallingAsleepStopsTheCreatureWhereItStands() {
        var rng = SeededRandom(state: 21)
        let walking = RoamPhase.walking(RoamWalk(on: .topEdge, from: 0, to: 140, start: t0, speed: 35))
        #expect(RoamRules.next(walking, inputs(at: 2, homing: .stay), using: &rng) == .stopped(at: .topEdge(70)))
        #expect(RoamRules.next(.resting(at: .topEdge(-300), until: t0 + 5), inputs(homing: .stay), using: &rng) == .stopped(at: .topEdge(-300)))
        #expect(RoamRules.next(.stopped(at: .topEdge(-300)), inputs(at: 600, homing: .stay), using: &rng) == .stopped(at: .topEdge(-300)))
        #expect(RoamPhase.stopped(at: .topEdge(-300)).spot(at: t0) == .topEdge(-300))
        #expect(RoamPhase.stopped(at: .topEdge(-300)).deadline == nil)
    }

    @Test func aSleeperPastTheEndOfANarrowedRangeIsMovedToItsEnd() {
        var rng = SeededRandom(state: 25)
        let narrowDock = RoamInputs(now: t0 + 10, range: range, dock: -300...300, homing: .stay)
        #expect(RoamRules.next(.stopped(at: .dock(500)), narrowDock, using: &rng) == .stopped(at: .dock(300)))
        #expect(RoamRules.next(.stopped(at: .dock(-420)), narrowDock, using: &rng) == .stopped(at: .dock(-300)))
        #expect(RoamRules.next(.stopped(at: .topEdge(-900)), inputs(homing: .stay), using: &rng) == .stopped(at: .topEdge(-800)))
        let pastTheEnd = RoamPhase.walking(RoamWalk(on: .dock, from: 0, to: 400, start: t0, speed: 35))
        #expect(RoamRules.next(pastTheEnd, narrowDock, using: &rng) == .stopped(at: .dock(300)))
    }

    @Test func fallingAsleepAtHomeStaysHome() {
        var rng = SeededRandom(state: 23)
        #expect(RoamRules.next(.home, inputs(homing: .stay), using: &rng) == .home)
        #expect(RoamRules.next(.resting(at: .topEdge(0), until: t0 + 5), inputs(homing: .stay), using: &rng) == .home)
    }

    @Test(arguments: 0..<20)
    func wakingRestsWhereItSleptThenRoams(seed: UInt64) {
        var rng = SeededRandom(state: seed)
        guard case .resting(let spot, let until) = RoamRules.next(.stopped(at: .topEdge(300)), inputs(at: 60), using: &rng) else {
            Issue.record("waking rests where it slept")
            return
        }
        #expect(spot == .topEdge(300))
        #expect((4...15).contains(until.timeIntervalSince(t0 + 60)))
    }

    @Test func wakingOutsideARangeThatNarrowedWhileItSleptWalksBackIn() {
        var rng = SeededRandom(state: 25)
        #expect(RoamRules.next(.stopped(at: .topEdge(600)), inputs(range: -200...200), using: &rng)
            == .walking(RoamWalk(on: .topEdge, from: 600, to: 200, start: t0, speed: RoamRules.walkSpeed)))
    }

    @Test func deadlinesAreWhenEachPhaseEndsByItself() {
        #expect(RoamPhase.home.deadline == nil)
        #expect(RoamPhase.resting(at: .topEdge(1), until: t0 + 6).deadline == t0 + 6)
        #expect(RoamPhase.walking(RoamWalk(on: .topEdge, from: 0, to: 70, start: t0, speed: 35)).deadline == t0 + 2)
    }
}

struct CursorCrossingTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let radius = BehaviourRules.watchRadius

    /// Seconds after `t0`, so float rounding in the times does not matter.
    func crossings(_ walk: RoamWalk, cursor: CursorOffset) -> [Double] {
        walk.crossings(of: cursor, radius: radius).map { ($0.timeIntervalSince(t0) * 1e6).rounded() / 1e6 }
    }

    @Test func approachingAStillCursorEntersItsRadiusOnce() {
        let walk = RoamWalk(on: .topEdge, from: 0, to: 400, start: t0, speed: 50)
        #expect(crossings(walk, cursor: CursorOffset(dx: 300, dy: 0)) == [3])
    }

    @Test func passingACursorEntersAndLeavesWhereTheCircleMeetsTheStrip() {
        let cursor = CursorOffset(dx: 0, dy: 90)
        #expect(crossings(RoamWalk(on: .topEdge, from: -400, to: 400, start: t0, speed: 50), cursor: cursor) == [5.6, 10.4])
        #expect(crossings(RoamWalk(on: .topEdge, from: 400, to: -400, start: t0, speed: 50), cursor: cursor) == [5.6, 10.4])
    }

    @Test(arguments: [CursorOffset(dx: 700, dy: 0), CursorOffset(dx: 100, dy: 200), CursorOffset(dx: -300, dy: 0)])
    func aWalkThatNeverReachesTheCursorHasNoCrossings(cursor: CursorOffset) {
        #expect(crossings(RoamWalk(on: .topEdge, from: 0, to: 400, start: t0, speed: 50), cursor: cursor).isEmpty)
    }

    @Test func startingInsideOnlyLeaves() {
        let walk = RoamWalk(on: .topEdge, from: 0, to: 400, start: t0, speed: 50)
        #expect(crossings(walk, cursor: CursorOffset(dx: 50, dy: 0)) == [4])
        #expect(crossings(walk, cursor: CursorOffset(dx: 300, dy: 0)).allSatisfy { $0 > 0 })
    }

    @Test func aWalkThatStaysInsideNeverCrosses() {
        #expect(crossings(RoamWalk(on: .topEdge, from: 0, to: 100, start: t0, speed: 50), cursor: CursorOffset(dx: 50, dy: 0)).isEmpty)
    }
}

struct HomingTests {
    static let free = HomingConditions(
        wander: .topEdge, panelOpen: false, sleeping: false, focusing: false, fullScreen: false, cursorNearHome: false, hasCreature: true, perch: .topEdge
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
        (with { $0.sleeping = true }, .stay),
        (with { $0.focusing = true }, .walk),
        (with { $0.cursorNearHome = true }, .run),
        (with { $0.cursorNearHome = true; $0.sleeping = true }, .stay),
        (with { $0.panelOpen = true }, .snap),
        (with { $0.fullScreen = true }, .snap),
        (with { $0.hasCreature = false }, .snap),
        (with { $0.panelOpen = true; $0.cursorNearHome = true }, .snap),
        (with { $0.fullScreen = true; $0.wander = .off }, .snap),
        (with { $0.wander = .dock }, .free),
        (with { $0.wander = .topEdgeAndDock }, .free),
        (with { $0.perch = .dock }, .free),
        (with { $0.perch = .dock; $0.cursorNearHome = true }, .free),
        (with { $0.perch = .dock; $0.panelOpen = true }, .snap),
        (with { $0.perch = .dock; $0.fullScreen = true }, .snap),
        (with { $0.perch = .dock; $0.hasCreature = false }, .snap),
        (with { $0.perch = .dock; $0.sleeping = true }, .stay),
        (with { $0.perch = .dock; $0.focusing = true }, .walk),
        (with { $0.perch = .dock; $0.wander = .off }, .walk),
        (with { $0.perch = .dock; $0.focusing = true; $0.cursorNearHome = true }, .walk),
    ])
    func eachConditionCallsTheCreatureHome(conditions: HomingConditions, expected: Homing) {
        #expect(RoamRules.homing(conditions) == expected)
    }
}

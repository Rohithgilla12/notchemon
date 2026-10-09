import Foundation
import Testing
@testable import Notchemon

struct PartyRoamTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let range: ClosedRange<Double> = -800...800

    func inputs(
        at seconds: TimeInterval = 0, range: ClosedRange<Double>? = nil, dock: ClosedRange<Double>? = nil,
        homing: Homing = .free, occupied: [Perch: [ClosedRange<Double>]], follower: Bool = false
    ) -> RoamInputs {
        RoamInputs(now: t0 + seconds, range: range ?? self.range, dock: dock, homing: homing, occupied: occupied, follower: follower)
    }

    static func around(_ points: Double...) -> [ClosedRange<Double>] {
        points.map { (point: Double) -> ClosedRange<Double> in (point - RoamRules.gap)...(point + RoamRules.gap) }
    }

    func isClear(_ x: Double, of spans: [ClosedRange<Double>]) -> Bool {
        !spans.contains { $0.lowerBound < x && x < $0.upperBound }
    }

    @Test(arguments: 0..<200)
    func walkTargetsKeepClearOfTheOthers(seed: UInt64) throws {
        var rng = SeededRandom(state: seed)
        let spans = Self.around(100, 420, -500)
        let next = RoamRules.next(.resting(at: .topEdge(-300), until: t0), inputs(occupied: [.topEdge: spans]), using: &rng)
        let walk = try #require(next.walk)
        #expect(isClear(walk.to, of: spans))
        #expect(range.contains(walk.to))
        #expect(abs(walk.to + 300) >= RoamRules.minimumStride)
    }

    @Test(arguments: 0..<200)
    func landingsKeepClearOfTheOthers(seed: UInt64) {
        var rng = SeededRandom(state: seed)
        let spans = Self.around(-200, 0, 200)
        let resting = RoamPhase.resting(at: .topEdge(300), until: t0)
        let next = RoamRules.next(resting, inputs(dock: -300...300, occupied: [.dock: spans]), using: &rng)
        if case .transferring(_, let to, _) = next {
            #expect(to.perch == .dock)
            #expect(isClear(to.x, of: spans))
        }
    }

    @Test(arguments: 0..<50)
    func aFullDockIsNeverHoppedTo(seed: UInt64) {
        var rng = SeededRandom(state: seed)
        let next = RoamRules.next(
            .resting(at: .topEdge(300), until: t0), inputs(dock: -100...100, occupied: [.dock: Self.around(-50, 50)]), using: &rng
        )
        #expect(next.perch == .topEdge)
    }

    @Test func withNoRoomItRestsWhereItIs() {
        var rng = SeededRandom(state: 4)
        let crowded: [Perch: [ClosedRange<Double>]] = [.topEdge: [-200 ... -40, 40...200]]
        let next = RoamRules.next(.resting(at: .topEdge(0), until: t0), inputs(range: -200...200, occupied: crowded), using: &rng)
        guard case .resting(let spot, let until) = next else {
            Issue.record("expected another rest, got \(next)")
            return
        }
        #expect(spot == .topEdge(0))
        #expect(until > t0)
    }

    @Test(arguments: 0..<100)
    func aFollowerNeverHeadsHome(seed: UInt64) {
        var rng = SeededRandom(state: seed)
        let homeSpan: [Perch: [ClosedRange<Double>]] = [.topEdge: Self.around(0)]
        let next = RoamRules.next(.resting(at: .topEdge(300), until: t0), inputs(occupied: homeSpan), using: &rng)
        if let walk = next.walk {
            #expect(abs(walk.to) >= RoamRules.gap)
        }
    }

    @Test(arguments: 0..<50)
    func aFollowerAtHomeHopsOutToAClearSpot(seed: UInt64) {
        var rng = SeededRandom(state: seed)
        let spans = Self.around(0, 300)
        let next = RoamRules.next(.home, inputs(occupied: [.topEdge: spans], follower: true), using: &rng)
        guard case .transferring(let from, let to, let start) = next else {
            Issue.record("a follower leaves home at once")
            return
        }
        #expect(from == .home)
        #expect(to.perch == .topEdge)
        #expect(isClear(to.x, of: spans))
        #expect(start == t0)
    }

    @Test func theLeaderRestsAtHomeWhileAFollowerWalksPastIt() {
        var rng = SeededRandom(state: 8)
        let next = RoamRules.next(.home, inputs(occupied: [.topEdge: Self.around(20)]), using: &rng)
        guard case .resting(let spot, _) = next else {
            Issue.record("the leader stays home, got \(next)")
            return
        }
        #expect(spot == .home)
    }

    @Test func aFollowerWithNowhereToGoWaitsAtHomeThenHopsOutWhenThereIsRoom() {
        var rng = SeededRandom(state: 8)
        let homeSpan: [Perch: [ClosedRange<Double>]] = [.topEdge: Self.around(0)]
        let waiting = RoamRules.next(.home, inputs(range: 0...0, occupied: homeSpan, follower: true), using: &rng)
        guard case .resting(let spot, let until) = waiting else {
            Issue.record("expected a wait at home, got \(waiting)")
            return
        }
        #expect(spot == .home)
        let later = until.timeIntervalSince(t0)
        let next = RoamRules.next(waiting, inputs(at: later, occupied: homeSpan, follower: true), using: &rng)
        guard case .transferring(let from, let to, _) = next else {
            Issue.record("expected a hop out of home, got \(next)")
            return
        }
        #expect(from == .home)
        #expect(abs(to.x) >= RoamRules.gap)
    }

    @Test func aFollowerWithOnlyTheDockOpenHopsOntoIt() {
        var rng = SeededRandom(state: 8)
        let next = RoamRules.next(.home, inputs(range: 0...0, dock: -300...300, occupied: [.topEdge: Self.around(0)], follower: true), using: &rng)
        guard case .transferring(_, let to, _) = next else {
            Issue.record("expected a hop to the Dock, got \(next)")
            return
        }
        #expect(to.perch == .dock)
    }

    @Test func aFollowerLeavingAVanishedDockWithNoRoomUpTopDropsOutOfSightAtHome() {
        var rng = SeededRandom(state: 8)
        let resting = RoamPhase.resting(at: .dock(40), until: t0 + 9)
        let crowded: [Perch: [ClosedRange<Double>]] = [.topEdge: [-200...200]]
        let next = RoamRules.next(resting, inputs(range: -200...200, occupied: crowded, follower: true), using: &rng)
        #expect(next == .transferring(from: .dock(40), to: .home, start: t0))
    }

    @Test func wakingBesideAnotherStepsToTheNearestClearSpot() {
        var rng = SeededRandom(state: 2)
        let next = RoamRules.next(.stopped(at: .topEdge(30)), inputs(occupied: [.topEdge: Self.around(60)]), using: &rng)
        #expect(next == .walking(RoamWalk(on: .topEdge, from: 30, to: 0, start: t0, speed: RoamRules.walkSpeed)))
    }

    @Test func wakingClearOfEveryoneRestsWhereItSlept() {
        var rng = SeededRandom(state: 2)
        let next = RoamRules.next(.stopped(at: .topEdge(-300)), inputs(occupied: [.topEdge: Self.around(60)]), using: &rng)
        guard case .resting(let spot, _) = next else {
            Issue.record("expected a rest, got \(next)")
            return
        }
        #expect(spot == .topEdge(-300))
    }

    @Test func homingStillTakesTheLeaderHomeThroughTheParty() {
        var rng = SeededRandom(state: 3)
        let crowded: [Perch: [ClosedRange<Double>]] = [.topEdge: Self.around(100, 200)]
        let next = RoamRules.next(.resting(at: .topEdge(300), until: t0 + 9), inputs(homing: .run, occupied: crowded), using: &rng)
        #expect(next == .returning(RoamWalk(on: .topEdge, from: 300, to: 0, start: t0, speed: RoamRules.runSpeed)))
    }

    @Test func occupiedCoversWhereEachOtherStandsAndIsHeaded() {
        let walk = RoamWalk(on: .topEdge, from: 100, to: 300, start: t0, speed: 50)
        let others: [RoamPhase] = [.walking(walk), .resting(at: .dock(-40), until: t0 + 5), .home]
        let spans = RoamRules.occupied(by: others, at: t0 + 2, follower: false)
        #expect(spans[.topEdge] == Self.around(200, 300))
        #expect(spans[.dock] == Self.around(-40))
        let hop = RoamPhase.transferring(from: .topEdge(500), to: .dock(80), start: t0)
        let asFollower = RoamRules.occupied(by: [hop], at: t0, follower: true)
        #expect(asFollower[.topEdge] == Self.around(0, 500))
        #expect(asFollower[.dock] == Self.around(80))
    }
}

struct FollowerHomingTests {
    static let free = HomingConditions(
        wander: .topEdge, panelOpen: false, sleeping: false, focusing: false, fullScreen: false, cursorNearHome: false,
        hasCreature: true, perch: .topEdge, leads: false
    )

    static func with(_ change: (inout HomingConditions) -> Void) -> HomingConditions {
        var conditions = free
        change(&conditions)
        return conditions
    }

    @Test(arguments: [
        (free, Homing.free),
        (with { $0.panelOpen = true }, .free),
        (with { $0.focusing = true }, .free),
        (with { $0.cursorNearHome = true }, .free),
        (with { $0.sleeping = true }, .stay),
        (with { $0.visitor = true }, .stay),
        (with { $0.fullScreen = true }, .snap),
        (with { $0.hasCreature = false }, .snap),
        (with { $0.wander = .off }, .snap),
        (with { $0.wander = .dock; $0.perch = .dock; $0.focusing = true }, .free),
    ])
    func aFollowerIgnoresEverythingThatCallsTheLeaderHome(conditions: HomingConditions, expected: Homing) {
        #expect(RoamRules.homing(conditions) == expected)
    }
}

/// Runs a party's roaming the way the app does, each member asked again at
/// its own deadlines, against the others' phases at that instant.
struct PartySimulation {
    let start: Date
    let range: ClosedRange<Double>
    let dock: ClosedRange<Double>?
    var phases: [RoamPhase]
    var generators: [SeededRandom]
    var now: Date
    var homing: Homing = .free

    init(members: Int, seed: UInt64, start: Date, range: ClosedRange<Double>, dock: ClosedRange<Double>?) {
        self.start = start
        self.range = range
        self.dock = dock
        phases = Array(repeating: .home, count: members)
        generators = (0..<members).map { (index: Int) -> SeededRandom in SeededRandom(state: seed &* 31 &+ UInt64(index)) }
        now = start
    }

    mutating func advance(_ member: Int) {
        var others = phases
        others.remove(at: member)
        let occupied = RoamRules.occupied(by: others, at: now, follower: member > 0)
        let inputs = RoamInputs(now: now, range: range, dock: dock, homing: homing, occupied: occupied, follower: member > 0)
        phases[member] = RoamRules.next(phases[member], inputs, using: &generators[member])
    }

    mutating func advanceAll() {
        for member in phases.indices { advance(member) }
    }

    /// Moves to the next deadline before `limit` and asks that member again,
    /// or returns false when none falls before it.
    mutating func step(until limit: Date) -> Bool {
        let due: [(Int, Date)] = phases.indices.compactMap { (index: Int) -> (Int, Date)? in
            phases[index].deadline.map { (index, $0) }
        }
        guard let next = due.min(by: { $0.1 < $1.1 }), next.1 < limit else { return false }
        now = max(now, next.1)
        advance(next.0)
        return true
    }

    /// Pairs of members resting on the same perch closer than the gap. A
    /// follower waiting out of sight at home is not standing anywhere.
    func crowdedRests() -> [String] {
        var resting: [(Int, RoamSpot)] = []
        for (index, phase) in phases.enumerated() {
            switch phase {
            case .resting(let spot, _) where !(index > 0 && spot == .home):
                resting.append((index, spot))
            case .home where index == 0:
                resting.append((index, .home))
            default:
                break
            }
        }
        var crowded: [String] = []
        for (offset, first) in resting.enumerated() {
            for second in resting.dropFirst(offset + 1) where first.1.perch == second.1.perch {
                let apart: Double = abs(first.1.x - second.1.x)
                if apart < RoamRules.gap - 1e-9 { crowded.append("\(first.0)@\(first.1.x) \(second.0)@\(second.1.x)") }
            }
        }
        return crowded
    }
}

struct PartyHourTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: [2, 3], [UInt64(1), 2, 3, 4, 5])
    func restingMembersNeverStandWithinTheGapOverAnHour(members: Int, seed: UInt64) {
        var party = PartySimulation(members: members, seed: seed, start: t0, range: -700...700, dock: -400...400)
        party.advanceAll()
        var steps = 0
        var crowded: [String] = []
        // A ten-minute nap every twenty, so members stop mid-walk and wake beside each other too.
        for block in 0..<3 {
            let napAt = t0 + Double(block) * 1_200 + 600
            while party.step(until: napAt) {
                steps += 1
                crowded += party.crowdedRests()
            }
            party.now = napAt
            party.homing = .stay
            party.advanceAll()
            party.now = napAt + 600
            party.homing = .free
            party.advanceAll()
            crowded += party.crowdedRests()
        }
        #expect(crowded.isEmpty, "members rested too close: \(crowded.prefix(5))")
        #expect(steps > 50 * members)
    }

    @Test(arguments: [UInt64(7), 8, 9])
    func followersLeaveHomeAndUseBothPerches(seed: UInt64) {
        var party = PartySimulation(members: 3, seed: seed, start: t0, range: -700...700, dock: -400...400)
        party.advanceAll()
        #expect(party.phases[1] != .home)
        #expect(party.phases[2] != .home)
        var perches: Set<String> = []
        while party.step(until: t0 + 3_600) {
            for phase in party.phases.dropFirst() { perches.insert(phase.perch == .dock ? "dock" : "top") }
        }
        #expect(perches == ["dock", "top"])
    }
}

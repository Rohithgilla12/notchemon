import Foundation
import Testing
@testable import Notchemon

struct PerchRulesTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let top: ClosedRange<Double> = -800...800
    let dock: ClosedRange<Double> = -500...500

    /// `dock: .some(nil)` closes the Dock; leaving it out keeps it open.
    func inputs(at seconds: TimeInterval = 0, homing: Homing = .free, top: ClosedRange<Double>? = nil, dock: ClosedRange<Double>?? = .none) -> RoamInputs {
        let open: ClosedRange<Double>? = switch dock {
        case .none: self.dock
        case .some(let range): range
        }
        return RoamInputs(now: t0 + seconds, range: top ?? self.top, dock: open, homing: homing)
    }

    func next(_ phase: RoamPhase, _ inputs: RoamInputs, seed: UInt64 = 1) -> RoamPhase {
        var rng = SeededRandom(state: seed)
        return RoamRules.next(phase, inputs, using: &rng)
    }

    @Test func withBothPerchesOpenAboutOneRestInFourHopsToARandomSpotOnTheOtherPerch() {
        let outcomes = (0..<400).map { next(.resting(at: .topEdge(300), until: t0), inputs(), seed: UInt64($0)) }
        let hops = outcomes.compactMap { phase -> (RoamSpot, RoamSpot, Date)? in
            guard case .transferring(let from, let to, let start) = phase else { return nil }
            return (from, to, start)
        }
        #expect((60...140).contains(hops.count))
        #expect(hops.allSatisfy { $0.0 == .topEdge(300) && $0.1.perch == .dock && dock.contains($0.1.x) && $0.2 == t0 })
        #expect(Set(hops.map(\.1.x)).count == hops.count)
        #expect(outcomes.allSatisfy { phase in
            if case .transferring = phase { return true }
            return phase.walk?.perch == .topEdge || phase.perch == .topEdge
        })

        let fromDock = (0..<400).compactMap { seed -> RoamSpot? in
            guard case .transferring(_, let to, _) = next(.resting(at: .dock(100), until: t0), inputs(), seed: UInt64(seed)) else { return nil }
            return to
        }
        #expect((60...140).contains(fromDock.count))
        #expect(fromDock.allSatisfy { $0.perch == .topEdge && top.contains($0.x) })
    }

    @Test(arguments: 0..<100)
    func withoutADockTheCreatureNeverHops(seed: UInt64) {
        let phase = next(.resting(at: .topEdge(300), until: t0), inputs(dock: .some(nil)), seed: seed)
        #expect(phase.walk?.perch == .topEdge || phase.perch == .topEdge)
        if case .transferring = phase { Issue.record("hopped with no Dock open") }
    }

    @Test func aHopShowsTheCreatureAtItsStartThenItsLandingAndRestsThere() throws {
        let hop = RoamPhase.transferring(from: .topEdge(100), to: .dock(-40), start: t0)
        #expect(hop.spot(at: t0 + 0.34) == .topEdge(100))
        #expect(hop.spot(at: t0 + 0.35) == .dock(-40))
        #expect(hop.deadline == t0 + 0.7)
        #expect(hop.perch == .dock)
        #expect(hop.touches(.topEdge) && hop.touches(.dock))
        #expect(hop.walk == nil)
        #expect(hop.farthestAlongTopEdge == 100)
        #expect(next(hop, inputs(at: 0.69)) == hop)
        guard case .resting(let spot, let until) = next(hop, inputs(at: 0.7)) else {
            Issue.record("a hop rests where it lands")
            return
        }
        #expect(spot == .dock(-40))
        #expect((4...15).contains(until.timeIntervalSince(t0 + 0.7)))
    }

    @Test(arguments: 0..<100)
    func onTheDockARestEitherHopsUpOrWalksAlongTheDockAndNeverHeadsForHome(seed: UInt64) throws {
        let phase = next(.resting(at: .dock(300), until: t0), inputs(), seed: seed)
        switch phase {
        case .transferring(let from, let to, _):
            #expect(from == .dock(300))
            #expect(to.perch == .topEdge)
        case .walking(let walk):
            #expect(walk.perch == .dock)
            #expect(walk.from == 300)
            #expect(dock.contains(walk.to))
            #expect(abs(walk.to - 300) >= RoamRules.minimumStride)
            #expect(walk.to != 0)
        default:
            Issue.record("expected a hop or a walk on the Dock, got \(phase)")
        }
        #expect(!RoamPhase.resting(at: .dock(300), until: t0).touches(.topEdge))
        #expect(RoamPhase.resting(at: .dock(300), until: t0).farthestAlongTopEdge == 0)
    }

    @Test(arguments: 0..<50)
    func onTheDockOnlyTheCreatureAlwaysHopsDownFromHomeAndBackUpLandsHome(seed: UInt64) {
        let dockOnly = inputs(top: 0...0)
        guard case .transferring(let from, let to, _) = next(.resting(at: .home, until: t0), dockOnly, seed: seed) else {
            Issue.record("home has no room to stride, so it hops to the Dock")
            return
        }
        #expect(from == .home)
        #expect(to.perch == .dock && dock.contains(to.x))
        if case .transferring(_, let up, _) = next(.resting(at: .dock(200), until: t0), dockOnly, seed: seed) {
            #expect(up == .home)
        }
    }

    @Test func aDockThatNarrowsPastTheCreatureWalksItBackAlongTheDock() {
        #expect(next(.resting(at: .dock(450), until: t0 + 5), inputs(dock: -300...300))
            == .walking(RoamWalk(on: .dock, from: 450, to: 300, start: t0, speed: RoamRules.walkSpeed)))
    }

    @Test func whenTheDockGoesTheCreatureOnItHopsUpToTheTopEdge() throws {
        let gone = inputs(at: 2, dock: .some(nil))
        let phases: [(RoamPhase, RoamSpot)] = [
            (.resting(at: .dock(100), until: t0 + 5), .dock(100)),
            (.asleep(at: .dock(100)), .dock(100)),
            (.walking(RoamWalk(on: .dock, from: 0, to: 140, start: t0, speed: 35)), .dock(70)),
        ]
        for (phase, spot) in phases {
            guard case .transferring(let from, let to, let start) = next(phase, gone) else {
                Issue.record("\(phase) should hop up")
                continue
            }
            #expect(from == spot)
            #expect(to.perch == .topEdge && top.contains(to.x))
            #expect(start == t0 + 2)
        }
    }

    @Test func whenTheDockGoesMidHopTheCreatureHeadingDownIsHomeAndOneHeadingUpCarriesOn() {
        let down = RoamPhase.transferring(from: .topEdge(100), to: .dock(-40), start: t0)
        #expect(next(down, inputs(at: 0.2, dock: .some(nil))) == .home)
        let up = RoamPhase.transferring(from: .dock(-40), to: .topEdge(100), start: t0)
        #expect(next(up, inputs(at: 0.2, dock: .some(nil))) == up)
    }

    @Test(arguments: [
        RoamPhase.resting(at: .dock(100), until: .distantFuture),
        .asleep(at: .dock(-100)),
        .walking(RoamWalk(on: .dock, from: 0, to: 300, start: Date(timeIntervalSince1970: 1_800_000_000), speed: 35)),
        .transferring(from: .topEdge(100), to: .dock(-40), start: Date(timeIntervalSince1970: 1_800_000_000)),
        .transferring(from: .dock(-40), to: .topEdge(100), start: Date(timeIntervalSince1970: 1_800_000_000)),
    ])
    func snappingHomeIsImmediateFromEitherPerchAndMidHop(phase: RoamPhase) {
        #expect(next(phase, inputs(at: 0.1, homing: .snap)) == .home)
    }

    @Test func fallingAsleepOnTheDockSleepsThereAndAHopLandsFirst() {
        let walking = RoamPhase.walking(RoamWalk(on: .dock, from: 0, to: 140, start: t0, speed: 35))
        #expect(next(walking, inputs(at: 2, homing: .stay)) == .asleep(at: .dock(70)))
        #expect(next(.asleep(at: .dock(70)), inputs(at: 600, homing: .stay)) == .asleep(at: .dock(70)))
        let hop = RoamPhase.transferring(from: .topEdge(100), to: .dock(-40), start: t0)
        #expect(next(hop, inputs(at: 0.2, homing: .stay)) == hop)
        #expect(next(hop, inputs(at: 0.7, homing: .stay)) == .asleep(at: .dock(-40)))
        #expect(next(.asleep(at: .dock(70)), inputs(homing: .stay, dock: .some(nil))) == .home)
    }

    @Test(arguments: [Homing.walk, .run])
    func calledHomeFromTheDockItHopsUpToTheTopEdgeThenWalksHome(homing: Homing) throws {
        let onDock = RoamPhase.walking(RoamWalk(on: .dock, from: 0, to: 140, start: t0, speed: 35))
        guard case .transferring(let from, let to, let start) = next(onDock, inputs(at: 2, homing: homing)) else {
            Issue.record("expected a hop up")
            return
        }
        #expect(from == .dock(70))
        #expect(to.perch == .topEdge && top.contains(to.x))
        let hop = RoamPhase.transferring(from: from, to: to, start: start)
        #expect(next(hop, inputs(at: 2.3, homing: homing)) == hop)
        let speed = homing == .run ? RoamRules.runSpeed : RoamRules.walkSpeed
        #expect(next(hop, inputs(at: 2.7, homing: homing)) == .returning(RoamWalk(on: .topEdge, from: to.x, to: 0, start: t0 + 2.7, speed: speed)))
    }

    @Test func wanderingOffMidHopDownLandsThenHopsBackUp() {
        let hop = RoamPhase.transferring(from: .topEdge(100), to: .dock(-40), start: t0)
        #expect(next(hop, inputs(at: 0.2, homing: .walk)) == hop)
        guard case .transferring(let from, let to, _) = next(hop, inputs(at: 0.7, homing: .walk, top: 0...0)) else {
            Issue.record("landing on the Dock while called home hops straight back up")
            return
        }
        #expect(from == .dock(-40))
        #expect(to == .home)
    }
}

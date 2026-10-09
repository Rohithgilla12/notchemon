import CoreGraphics
import Foundation
import Testing
@testable import Notchemon

@MainActor
struct FollowerPoseTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Each anim's frames carry their state and facing as attribution, so a test can tell them apart.
    static func frames(_ state: SpriteState, _ facing: Facing) -> SpriteFrames {
        SpriteFrames(
            frames: [FakeProvider.image()], durations: [0.2], directional: true, loops: state.loops,
            attribution: Attribution(authors: ["\(state)/\(facing)"], source: "test", license: "test", url: URL(string: "https://example.test")!)
        )
    }

    let sprites: SpriteSet = {
        var anims: [SpriteState: [Facing: SpriteFrames]] = [:]
        for state in SpriteState.allCases where state != .sitting {
            for facing in Facing.front {
                anims[state, default: [:]][facing] = FollowerPoseTests.frames(state, facing)
            }
        }
        return SpriteSet(bounds: SpriteRenderingTests.measured, anims: anims)
    }()

    func pose(
        _ roam: RoamPhase, on perch: Perch = .topEdge, look: FollowerLook = FollowerLook(), behaviour: Behaviour = .idle
    ) -> SpritePose? {
        var snapshot = CompanionSnapshot()
        snapshot.behaviour = behaviour
        return SpritePose(follower: sprites, look: look, snapshot, roam: roam, on: perch)
    }

    func shown(_ pose: SpritePose?) -> String? {
        pose?.show?.loop.attribution?.authors.first
    }

    @Test(arguments: [
        RoamPhase.home, .resting(at: .home, until: Date(timeIntervalSince1970: 1_800_000_009)), .stopped(at: .home),
    ])
    func aFollowerAtHomeIsOutOfSight(roam: RoamPhase) {
        #expect(pose(roam, on: .topEdge) == nil)
        #expect(pose(roam, on: .dock) == nil)
    }

    @Test(arguments: [RoamSpot.topEdge(300), .dock(-120)])
    func hoppingOutOfHomeItIsSeenOnlyArriving(landing: RoamSpot) throws {
        let hop = RoamPhase.transferring(from: .home, to: landing, start: t0)
        let there = try #require(pose(hop, on: landing.perch))
        #expect(there.track == .arrive(landing.x, start: t0 + RoamRules.transferHalf))
        let other: Perch = landing.perch == .topEdge ? .dock : .topEdge
        #expect(pose(hop, on: other) == nil)
    }

    @Test func droppingIntoHomeItIsSeenOnlyLeaving() throws {
        let hop = RoamPhase.transferring(from: .dock(40), to: .home, start: t0)
        #expect(try #require(pose(hop, on: .dock)).track == .leave(40, start: t0))
        #expect(pose(hop, on: .topEdge) == nil)
    }

    @Test func aHopBetweenPerchesAwayFromHomeLeavesAndArrivesLikeTheLeaders() throws {
        let hop = RoamPhase.transferring(from: .topEdge(200), to: .dock(40), start: t0)
        #expect(try #require(pose(hop, on: .topEdge)).track == .leave(200, start: t0))
        #expect(try #require(pose(hop, on: .dock)).track == .arrive(40, start: t0 + RoamRules.transferHalf))
    }

    @Test func walkingPlaysItsOwnWalkTheWayItGoes() throws {
        let walk = RoamWalk(on: .topEdge, from: 300, to: 100, start: t0, speed: RoamRules.walkSpeed)
        let walking = try #require(pose(.walking(walk)))
        #expect(shown(walking) == "walking/left")
        #expect(walking.show?.facing == .left)
        #expect(walking.track == .walk(walk))
        #expect(!walking.fidgets)
    }

    @Test func restingItStandsOnItsIdleRestFrameAndFidgets() throws {
        let resting = try #require(pose(.resting(at: .topEdge(-250), until: t0 + 5)))
        #expect(shown(resting) == "idle/down")
        #expect(resting.show?.playback == .hold)
        #expect(resting.track == .still(-250))
        #expect(resting.fidgets)
        #expect(!resting.tucked)
        #expect(resting.flashToken == 0)
    }

    @Test func itWatchesTheCursorFromItsOwnSpotAndHopsInThatFacing() throws {
        let look = FollowerLook(facing: .downLeft, hops: 2)
        let watching = try #require(pose(.resting(at: .topEdge(-250), until: t0 + 5), look: look))
        #expect(shown(watching) == "idle/downLeft")
        #expect(watching.show?.oneShot?.serial == 2)
        #expect(watching.show?.oneShot?.state == .hop)
        #expect(watching.show?.oneShot?.frames.attribution?.authors == ["hop/downLeft"])
    }

    @Test func itSleepsWithTheLeaderWhereverItIsAndNeverTucks() throws {
        let asleep = try #require(pose(.stopped(at: .dock(80)), on: .dock, look: FollowerLook(facing: .left), behaviour: .sleeping))
        #expect(shown(asleep) == "sleeping/down")
        #expect(!asleep.tucked)
    }

    @Test func theLeadersCelebrationIsNotAFollowersOwn() throws {
        let celebrating = try #require(pose(.resting(at: .topEdge(200), until: t0 + 5), behaviour: .celebrating(.levelUp(9))))
        #expect(shown(celebrating) == "idle/down")
    }
}

@MainActor
struct PartyTests {
    @Test func eachMemberGetsItsOwnRoamerAndKeepsItAcrossARoleSwap() throws {
        let party = Party()
        party.sync(leader: 1, followers: [2, 3])
        let leader = try #require(party.roamers[1])
        let follower = try #require(party.roamers[2])
        #expect(party.members == [1, 2, 3])
        #expect(party.all.map(\.partner) == [1, 2, 3])
        party.sync(leader: 2, followers: [1])
        #expect(party.roamers[2] === follower)
        #expect(party.roamers[1] === leader)
        #expect(party.roamers[3] == nil)
        #expect(party.leaderRoamer === follower)
        party.sync(leader: nil, followers: [])
        #expect(party.roamers.isEmpty)
    }

    @Test func onlyAFollowerKeepsClearOfHome() {
        let party = Party()
        party.sync(leader: 1, followers: [2])
        #expect(party.occupied(for: 1).isEmpty)
        #expect(party.occupied(for: 2)[.topEdge] == [(-RoamRules.gap)...RoamRules.gap])
    }

    @Test func aFollowerFacesAndHopsAtTheCursorFromItsOwnSpot() async throws {
        let party = Party()
        var events: [CompanionEvent] = []
        party.onEvent = { events.append($0) }
        party.sync(leader: 1, followers: [2])
        let follower = try #require(party.roamers[2])
        follower.update(range: -800...800, dock: nil, homing: .free)
        guard case .transferring(_, let landing, _) = follower.phase else {
            Issue.record("a follower hops out of home, got \(follower.phase)")
            return
        }
        let centre: (RoamSpot) -> CGPoint? = { CGPoint(x: $0.x, y: 0) }
        party.cursorMoved(to: CGPoint(x: landing.x - 60, y: -60), hopsEnabled: true, centre: centre)
        #expect(party.looks[2]?.facing == nil, "still out of sight at home")
        try await Task.sleep(for: .seconds(RoamRules.transferHalf + 0.05))
        party.cursorMoved(to: CGPoint(x: landing.x + 400, y: 0), hopsEnabled: true, centre: centre)
        #expect(party.looks[2] == FollowerLook(facing: nil, hops: 0))
        party.cursorMoved(to: CGPoint(x: landing.x - 60, y: -60), hopsEnabled: true, centre: centre)
        #expect(party.looks[2] == FollowerLook(facing: .downLeft, hops: 1))
        #expect(events == [.hopped(partner: 2)])
        party.cursorMoved(to: CGPoint(x: landing.x + 60, y: -60), hopsEnabled: true, centre: centre)
        #expect(party.looks[2] == FollowerLook(facing: .downRight, hops: 1))
        #expect(events.count == 1)
    }

    @Test func noHopWhenHoppingIsOff() async throws {
        let party = Party()
        party.sync(leader: 1, followers: [2])
        let follower = try #require(party.roamers[2])
        follower.update(range: -800...800, dock: nil, homing: .free)
        try await Task.sleep(for: .seconds(RoamRules.transferHalf + 0.05))
        let x = follower.phase.spot(at: Date()).x
        let centre: (RoamSpot) -> CGPoint? = { CGPoint(x: $0.x, y: 0) }
        party.cursorMoved(to: CGPoint(x: x + 400, y: 0), hopsEnabled: false, centre: centre)
        party.cursorMoved(to: CGPoint(x: x, y: -60), hopsEnabled: false, centre: centre)
        #expect(party.looks[2] == FollowerLook(facing: .down, hops: 0))
    }
}

import CoreGraphics
import Foundation
import Testing
@testable import Notchemon

@MainActor
struct SpritePoseTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let idle = SpriteFrames(frames: [FakeProvider.image()], durations: [1])
    let left = SpriteFrames(frames: [FakeProvider.image()], durations: [0.2], directional: true)
    let right = SpriteFrames(frames: [FakeProvider.image()], durations: [0.2], directional: true)
    let sleep = SpriteFrames(frames: [FakeProvider.image(), FakeProvider.image()], durations: [0.5, 0.5])

    func snapshot(behaviour: Behaviour = .idle) -> CompanionSnapshot {
        var snapshot = CompanionSnapshot()
        snapshot.behaviour = behaviour
        snapshot.sprite = SpriteShow(
            loop: idle, loopState: .idle, playback: .hold, facing: .down,
            bounds: SpriteRenderingTests.measured, oneShot: nil, walk: WalkCycle(left: left, right: right)
        )
        return snapshot
    }

    func topEdgePose(_ snapshot: CompanionSnapshot, _ roam: RoamPhase, expanded: Bool) throws -> SpritePose {
        try #require(SpritePose(snapshot, roam: roam, on: .topEdge, expanded: expanded))
    }

    @Test(arguments: [(-200.0, Facing.left), (200, .right)])
    func walkingPlaysTheWalkFacingTheWayItGoesAndMovesAlongTheStrip(to: Double, facing: Facing) throws {
        let walk = RoamWalk(on: .topEdge, from: 0, to: to, start: t0, speed: RoamRules.walkSpeed)
        let pose = try topEdgePose(snapshot(), .walking(walk), expanded: false)
        let show = try #require(pose.show)
        #expect(show.loop.frames.first === (facing == .left ? left : right).frames.first)
        #expect(show.loopState == .walking)
        #expect(show.playback == .cycle)
        #expect(show.facing == facing)
        #expect(pose.track == .walk(walk))
        #expect(!pose.fidgets)
        #expect(pose.fit == .peek)
    }

    @Test func restingAwayKeepsItsIdleLoopWhereItStopped() throws {
        let pose = try topEdgePose(snapshot(), .resting(at: .topEdge(-150), until: t0 + 5), expanded: false)
        #expect(pose.show?.loop.frames.first === idle.frames.first)
        #expect(pose.show?.loopState == .idle)
        #expect(pose.track == .still(-150))
        #expect(pose.fidgets)
    }

    @Test func theOpenPanelShowsTheCreatureInItsSlotWhereverItWandered() throws {
        let walk = RoamWalk(on: .topEdge, from: 0, to: 300, start: t0, speed: RoamRules.walkSpeed)
        for roam in [RoamPhase.walking(walk), .resting(at: .topEdge(300), until: t0 + 5)] {
            let pose = try topEdgePose(snapshot(), roam, expanded: true)
            #expect(pose.track == .still(0))
            #expect(pose.show?.loopState == .idle)
            #expect(pose.fit == .contain)
        }
    }

    @Test func asleepItTucksUpOnlyOnceItIsHome() throws {
        let returning = RoamPhase.returning(RoamWalk(on: .topEdge, from: 200, to: 0, start: t0, speed: RoamRules.walkSpeed))
        #expect(try !topEdgePose(snapshot(behaviour: .sleeping), returning, expanded: false).tucked)
        #expect(try !topEdgePose(snapshot(behaviour: .sleeping), .asleep(at: .topEdge(200)), expanded: false).tucked)
        #expect(try topEdgePose(snapshot(behaviour: .sleeping), .home, expanded: false).tucked)
        #expect(try !topEdgePose(snapshot(behaviour: .sleeping), .home, expanded: true).tucked)
        #expect(try !topEdgePose(snapshot(), .home, expanded: false).tucked)
    }

    @Test func asleepAwayFromHomeItPlaysTheSleepLoopWhereItStopped() throws {
        var sleeping = snapshot(behaviour: .sleeping)
        sleeping.sprite?.loop = sleep
        sleeping.sprite?.loopState = .sleeping
        sleeping.sprite?.playback = .cycle
        let asleep = try topEdgePose(sleeping, .asleep(at: .topEdge(-150)), expanded: false)
        #expect(asleep.show?.loopState == .sleeping)
        #expect(asleep.show?.loop.frames.first === sleep.frames.first)
        #expect(asleep.track == .still(-150))
        #expect(!asleep.tucked)

        let walk = RoamWalk(on: .topEdge, from: 0, to: 300, start: t0, speed: RoamRules.walkSpeed)
        let midWalk = try topEdgePose(sleeping, .walking(walk), expanded: false)
        #expect(midWalk.show?.loopState == .sleeping)
        #expect(midWalk.show?.loop.frames.first === sleep.frames.first)
        #expect(midWalk.show?.facing == .down)
    }

    @Test func theCursorIsMeasuredFromTheCreaturesLiveSpot() throws {
        let layout = try #require(NotchGeometry.layout(
            for: ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), safeAreaTop: 32, auxiliaryTopLeftWidth: 764, auxiliaryTopRightWidth: 764),
            virtualNotchEnabled: false, wander: .topEdge
        ))
        let metrics = PanelMetrics(layout: layout)
        let home = metrics.spriteCentre(expanded: false, roamX: 0, panelFrame: layout.expanded)
        #expect(home == CGPoint(x: 864, y: 1063))
        let walk = RoamPhase.walking(RoamWalk(on: .topEdge, from: 0, to: -350, start: t0, speed: RoamRules.walkSpeed))
        let midWalk = metrics.spriteCentre(expanded: false, roamX: walk.spot(at: t0 + 2).x, panelFrame: layout.expanded)
        #expect(midWalk == CGPoint(x: 794, y: 1063))
        #expect(metrics.spriteCentre(expanded: true, roamX: -70, panelFrame: layout.expanded) == metrics.spriteCentre(expanded: true, roamX: 0, panelFrame: layout.expanded))
    }

    @Test func eachPerchShowsTheCreatureOnlyWhileItIsThere() throws {
        let walk = RoamWalk(on: .dock, from: 0, to: -200, start: t0, speed: RoamRules.walkSpeed)
        let onDock = try #require(SpritePose(snapshot(), roam: .walking(walk), on: .dock, expanded: false))
        #expect(onDock.track == .walk(walk))
        #expect(onDock.show?.loopState == .walking)
        #expect(onDock.show?.facing == .left)
        #expect(onDock.fit == .peek)
        #expect(SpritePose(snapshot(), roam: .walking(walk), on: .topEdge, expanded: false) == nil)
        #expect(SpritePose(snapshot(), roam: .home, on: .dock, expanded: false) == nil)
        #expect(SpritePose(snapshot(), roam: .resting(at: .topEdge(40), until: t0), on: .dock, expanded: false) == nil)
        #expect(try #require(SpritePose(snapshot(), roam: .asleep(at: .dock(40)), on: .dock, expanded: false)).track == .still(40))
    }

    @Test func theOpenPanelShowsTheCreatureInTheNotchEvenFromTheDock() throws {
        let resting = RoamPhase.resting(at: .dock(120), until: t0 + 5)
        #expect(try topEdgePose(snapshot(), resting, expanded: true).track == .still(0))
        #expect(SpritePose(snapshot(), roam: resting, on: .dock, expanded: true) == nil)
    }

    @Test func aHopLeavesOnePerchThenArrivesOnTheOtherHalfwayThrough() throws {
        let hop = RoamPhase.transferring(from: .topEdge(-300), to: .dock(80), start: t0)
        let leaving = try topEdgePose(snapshot(), hop, expanded: false)
        #expect(leaving.track == .leave(-300, start: t0))
        #expect(!leaving.fidgets)
        #expect(leaving.show?.loopState == .idle)
        let arriving = try #require(SpritePose(snapshot(), roam: hop, on: .dock, expanded: false))
        #expect(arriving.track == .arrive(80, start: t0 + RoamRules.transferHalf))
        #expect(!arriving.tucked)
    }
}

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

    func snapshot(behaviour: Behaviour = .idle) -> CompanionSnapshot {
        var snapshot = CompanionSnapshot()
        snapshot.behaviour = behaviour
        snapshot.sprite = SpriteShow(
            loop: idle, loopState: .idle, playback: .hold, facing: .down,
            bounds: SpriteRenderingTests.measured, oneShot: nil, walk: WalkCycle(left: left, right: right)
        )
        return snapshot
    }

    @Test(arguments: [(-200.0, Facing.left), (200, .right)])
    func walkingPlaysTheWalkFacingTheWayItGoesAndMovesAlongTheStrip(to: Double, facing: Facing) throws {
        let walk = RoamWalk(from: 0, to: to, start: t0, speed: RoamRules.walkSpeed)
        let pose = SpritePose(snapshot(), roam: .walking(walk), expanded: false, at: t0 + 1)
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
        let pose = SpritePose(snapshot(), roam: .resting(at: -150, until: t0 + 5), expanded: false, at: t0)
        #expect(pose.show?.loop.frames.first === idle.frames.first)
        #expect(pose.show?.loopState == .idle)
        #expect(pose.track == .still(-150))
        #expect(pose.fidgets)
    }

    @Test func theOpenPanelShowsTheCreatureInItsSlotWhereverItWandered() throws {
        let walk = RoamWalk(from: 0, to: 300, start: t0, speed: RoamRules.walkSpeed)
        for roam in [RoamPhase.walking(walk), .resting(at: 300, until: t0 + 5)] {
            let pose = SpritePose(snapshot(), roam: roam, expanded: true, at: t0 + 1)
            #expect(pose.track == .still(0))
            #expect(pose.show?.loopState == .idle)
            #expect(pose.fit == .contain)
        }
    }

    @Test func asleepItTucksUpOnlyOnceItIsHome() {
        let returning = RoamPhase.returning(RoamWalk(from: 200, to: 0, start: t0, speed: RoamRules.walkSpeed))
        #expect(!SpritePose(snapshot(behaviour: .sleeping), roam: returning, expanded: false, at: t0 + 1).tucked)
        #expect(SpritePose(snapshot(behaviour: .sleeping), roam: .home, expanded: false, at: t0).tucked)
        #expect(!SpritePose(snapshot(behaviour: .sleeping), roam: .home, expanded: true, at: t0).tucked)
        #expect(!SpritePose(snapshot(), roam: .home, expanded: false, at: t0).tucked)
    }

    @Test func theCursorIsMeasuredFromTheCreaturesLiveSpot() throws {
        let layout = try #require(NotchGeometry.layout(
            for: ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), safeAreaTop: 32, auxiliaryTopLeftWidth: 764, auxiliaryTopRightWidth: 764),
            virtualNotchEnabled: false, wander: .topEdge
        ))
        let metrics = PanelMetrics(layout: layout)
        let home = metrics.spriteCentre(expanded: false, roamX: 0, panelFrame: layout.expanded)
        #expect(home == CGPoint(x: 864, y: 1063))
        let walk = RoamPhase.walking(RoamWalk(from: 0, to: -350, start: t0, speed: RoamRules.walkSpeed))
        let midWalk = metrics.spriteCentre(expanded: false, roamX: walk.x(at: t0 + 2), panelFrame: layout.expanded)
        #expect(midWalk == CGPoint(x: 794, y: 1063))
        #expect(metrics.spriteCentre(expanded: true, roamX: -70, panelFrame: layout.expanded) == metrics.spriteCentre(expanded: true, roamX: 0, panelFrame: layout.expanded))
    }
}

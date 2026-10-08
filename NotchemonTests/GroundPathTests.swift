import AppKit
import Testing
@testable import Notchemon

@MainActor
struct GroundPathTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    /// This Mac's auto-hiding Dock shown, measured from the middle of the walk along the screen's bottom.
    let shown = GroundStep(span: -744...744, height: 90)
    let climb = GroundPath.climb

    func heights(_ path: GroundPath) -> [Double] { path.keys.map(\.height) }
    func times(_ path: GroundPath) -> [Double] { path.keys.map { ($0.at.timeIntervalSince(t0) * 1000).rounded() / 1000 } }

    @Test func underAHiddenDockTheGroundIsTheFloor() {
        let path = GroundPath.plan(.still(300), on: nil, from: 0, at: t0)
        #expect(heights(path) == [0])
        #expect(path.final == 0)
    }

    @Test func aRevealRaisesACreatureInsideTheSpanOntoTheDockOverOneClimb() {
        let path = GroundPath.plan(.still(300), on: shown, from: 0, at: t0)
        #expect(heights(path) == [0, 90])
        #expect(times(path) == [0, climb])
        #expect(path.height(at: t0 + climb / 2) == 45)
        #expect(path.height(at: t0 + 5) == 90)
    }

    @Test func aRevealLeavesACreatureOutsideTheSpanOnTheFloor() {
        let path = GroundPath.plan(.still(800), on: shown, from: 0, at: t0)
        #expect(heights(path) == [0])
    }

    @Test func aHideDropsItBackToTheFloorFromWhereverItStands() {
        let path = GroundPath.plan(.still(300), on: nil, from: 90, at: t0)
        #expect(heights(path) == [90, 0])
        #expect(times(path) == [0, climb])
        let midRise = GroundPath.plan(.still(300), on: nil, from: 45, at: t0)
        #expect(heights(midRise) == [45, 0])
    }

    @Test func aViewMadeOnAShownDockStartsOnItWithoutClimbing() {
        let path = GroundPath.plan(.arrive(300, start: t0), on: shown, from: nil, at: t0)
        #expect(heights(path) == [90])
    }

    @Test func aRevealMidWalkRisesNowAndDropsAsTheWalkLeavesTheSpan() {
        let walk = RoamWalk(on: .dock, from: -800, to: 800, start: t0, speed: 35)
        let now = t0 + 10
        let path = GroundPath.plan(.walk(walk), on: shown, from: 0, at: now)
        let leaves = (744.0 + 800) / 35
        #expect(heights(path) == [0, 90, 90, 0])
        #expect(times(path) == [10, 10 + climb, leaves - climb / 2, leaves + climb / 2].map { ($0 * 1000).rounded() / 1000 })
        #expect(path.height(at: t0 + leaves) == 45)
        #expect(path.final == 0)
    }

    @Test(arguments: [(-800.0, 800.0), (800, -800)])
    func aWalkAcrossTheWholeShownDockStepsUpAtOneEndAndDownAtTheOther(from: Double, to: Double) {
        let walk = RoamWalk(on: .dock, from: from, to: to, start: t0, speed: 35)
        let path = GroundPath.plan(.walk(walk), on: shown, from: 0, at: t0)
        let enters = 56.0 / 35
        let leaves = (800.0 + 744) / 35
        #expect(heights(path) == [0, 0, 90, 90, 0])
        #expect(times(path) == [0, enters - climb / 2, enters + climb / 2, leaves - climb / 2, leaves + climb / 2].map { ($0 * 1000).rounded() / 1000 })
    }

    @Test func aWalkThatStaysOnTheFloorOrOnTheDockNeverClimbs() {
        let below = RoamWalk(on: .dock, from: 760, to: 830, start: t0, speed: 35)
        #expect(heights(GroundPath.plan(.walk(below), on: shown, from: 0, at: t0)) == [0])
        let along = RoamWalk(on: .dock, from: -500, to: 500, start: t0, speed: 35)
        #expect(heights(GroundPath.plan(.walk(along), on: shown, from: 90, at: t0)) == [90])
    }

    @Test func aDockPoseChangesWithTheShownDock() throws {
        var snapshot = CompanionSnapshot()
        snapshot.sprite = nil
        let onDock = try #require(SpritePose(snapshot, roam: .resting(at: .dock(300), until: t0), on: .dock, expanded: false, ground: shown))
        #expect(onDock.ground == shown)
        let hidden = try #require(SpritePose(snapshot, roam: .resting(at: .dock(300), until: t0), on: .dock, expanded: false))
        #expect(hidden != onDock)
    }

    @Test func aRevealMidWalkKeepsTheWalkPlayingAndAddsTheRise() throws {
        let walk = RoamWalk(on: .dock, from: -800, to: 800, start: Date() - 10, speed: 35)
        var pose = SpritePose(track: .walk(walk))
        let view = SpriteHostView(pose: pose)
        view.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        view.layout()
        let sprite = try #require(view.layer?.sublayers?.first)
        let stride = try #require(sprite.animation(forKey: "walk"))
        #expect(sprite.animation(forKey: "ground") == nil)
        #expect(sprite.position.y == 22)

        pose.ground = shown
        view.apply(pose)
        let after = try #require(sprite.animation(forKey: "walk"))
        #expect(after === stride)
        let rise = try #require(sprite.animation(forKey: "ground") as? CAKeyframeAnimation)
        #expect(rise.isAdditive)
        #expect(rise.values as? [Double] == [0, 90, 90, 0])
        #expect(sprite.position.y == 22)
    }
}

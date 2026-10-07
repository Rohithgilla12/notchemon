import Testing
@testable import Notchemon

struct BehaviourRulesTests {
    let calm = BehaviourInputs(
        secondsSinceInput: 1,
        cursorOffset: nil,
        secondsSinceCursorNear: 60,
        stashCount: 0,
        celebration: nil,
        sleepEnabled: true
    )

    @Test func defaultsToIdle() {
        #expect(BehaviourRules.resolve(calm) == .idle)
    }

    @Test func sleepsAfterTenMinutesWithoutInput() {
        var input = calm
        input.secondsSinceInput = 599
        #expect(BehaviourRules.resolve(input) == .idle)
        input.secondsSinceInput = 600
        #expect(BehaviourRules.resolve(input) == .sleeping)
    }

    @Test func sleepThresholdCanBeOverridden() {
        var input = calm
        input.sleepAfter = 5
        input.secondsSinceInput = 4
        #expect(BehaviourRules.resolve(input) == .idle)
        input.secondsSinceInput = 5
        #expect(BehaviourRules.resolve(input) == .sleeping)
    }

    @Test func sleepToggleOffKeepsItAwake() {
        var input = calm
        input.secondsSinceInput = 3600
        input.sleepEnabled = false
        #expect(BehaviourRules.resolve(input) == .idle)
    }

    @Test func facesTheCursorInTwoDimensions() {
        var input = calm
        input.cursorOffset = CursorOffset(dx: -60, dy: -60)
        #expect(BehaviourRules.resolve(input) == .watching(facing: .downLeft))
        input.cursorOffset = CursorOffset(dx: 60, dy: -60)
        #expect(BehaviourRules.resolve(input) == .watching(facing: .downRight))
        input.cursorOffset = CursorOffset(dx: 0, dy: 80)
        #expect(BehaviourRules.resolve(input) == .watching(facing: .up))
    }

    @Test func keepsWatchingBrieflyAfterCursorLeaves() {
        var input = calm
        input.secondsSinceCursorNear = 1.5
        #expect(BehaviourRules.resolve(input) == .watching(facing: .down))
        input.secondsSinceCursorNear = 2
        #expect(BehaviourRules.resolve(input) == .idle)
    }

    @Test func holdsWhenStashHasItems() {
        var input = calm
        input.stashCount = 2
        #expect(BehaviourRules.resolve(input) == .holding)
    }

    @Test func celebrationOverridesEverything() {
        var input = calm
        input.secondsSinceInput = 9999
        input.stashCount = 3
        input.cursorOffset = CursorOffset(dx: 10, dy: 0)
        input.celebration = .levelUp(7)
        #expect(BehaviourRules.resolve(input) == .celebrating(.levelUp(7)))
    }
}

struct SpriteChoreographyTests {
    @Test(arguments: [
        (Behaviour.idle, SpriteState.idle),
        (.watching(facing: .left), .idle),
        (.holding, .idle),
        (.celebrating(.levelUp(3)), .idle),
        (.sleeping, .sleeping),
    ])
    func loopForEachBehaviour(behaviour: Behaviour, expected: SpriteState) {
        #expect(SpriteChoreography.loop(for: behaviour) == expected)
    }

    @Test func cursorEnteringTheNotchHops() {
        #expect(SpriteChoreography.oneShot(for: .cursorEnteredNotch) == .hop)
    }

    @Test(arguments: [
        (Behaviour.idle, Behaviour.celebrating(.levelUp(4)), SpriteState?.some(.celebrating)),
        (.celebrating(.levelUp(4)), .celebrating(.evolution(from: 1, to: 2)), .celebrating),
        (.sleeping, .celebrating(.levelUp(4)), .celebrating),
        (.sleeping, .idle, .wake),
        (.sleeping, .watching(facing: .down), .wake),
        (.idle, .sleeping, nil),
        (.celebrating(.levelUp(4)), .idle, nil),
        (.idle, .watching(facing: .right), nil),
        (.watching(facing: .right), .watching(facing: .left), nil),
        (.idle, .holding, nil),
    ])
    func oneShotOnBehaviourChange(from previous: Behaviour, to next: Behaviour, expected: SpriteState?) {
        #expect(SpriteChoreography.oneShot(for: .behaviourChanged(from: previous, to: next)) == expected)
    }
}

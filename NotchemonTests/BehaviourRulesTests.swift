import Testing
@testable import Notchemon

struct BehaviourRulesTests {
    let calm = BehaviourInputs(
        secondsSinceInput: 1,
        cursorOffsetX: nil,
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

    @Test func sleepToggleOffKeepsItAwake() {
        var input = calm
        input.secondsSinceInput = 3600
        input.sleepEnabled = false
        #expect(BehaviourRules.resolve(input) == .idle)
    }

    @Test func gazeFollowsCursorAndClamps() {
        var input = calm
        input.cursorOffsetX = 75
        #expect(BehaviourRules.resolve(input) == .watching(gaze: 0.5))
        input.cursorOffsetX = -500
        #expect(BehaviourRules.resolve(input) == .watching(gaze: -1))
    }

    @Test func keepsWatchingBrieflyAfterCursorLeaves() {
        var input = calm
        input.secondsSinceCursorNear = 1.5
        #expect(BehaviourRules.resolve(input) == .watching(gaze: 0))
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
        input.celebration = .levelUp(7)
        #expect(BehaviourRules.resolve(input) == .celebrating(.levelUp(7)))
    }
}

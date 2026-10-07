import Testing
@testable import Notchemon

struct XPRulesTests {
    let stageOne = Species(id: 4, name: "stage-one", evolvesTo: 5, evolvesAtLevel: 16)
    let finalStage = Species(id: 6, name: "final-stage", evolvesTo: nil, evolvesAtLevel: nil)

    @Test func xpToNextLevelScalesWithLevel() {
        #expect(XPRules.xpToNextLevel(from: 5) == 200)
        #expect(XPRules.xpToNextLevel(from: 10) == 400)
    }

    @Test func oneSessionBelowThresholdOnlyAddsXP() {
        let (next, events) = XPRules.award(100, to: .starter(4), species: stageOne)
        #expect(next == Progress(speciesId: 4, level: 5, xp: 100))
        #expect(events.isEmpty)
    }

    @Test func crossingThresholdLevelsUpAndKeepsRemainder() {
        let (next, events) = XPRules.award(250, to: .starter(4), species: stageOne)
        #expect(next == Progress(speciesId: 4, level: 6, xp: 50))
        #expect(events == [.levelledUp(to: 6)])
    }

    @Test func largeAwardRollsOverSeveralLevels() {
        let (next, events) = XPRules.award(200 + 240 + 10, to: .starter(4), species: stageOne)
        #expect(next.level == 7)
        #expect(next.xp == 10)
        #expect(events == [.levelledUp(to: 6), .levelledUp(to: 7)])
    }

    @Test func reachingEvolutionLevelReportsEvolution() {
        let progress = Progress(speciesId: 4, level: 15, xp: 0)
        let (next, events) = XPRules.award(600, to: progress, species: stageOne)
        #expect(next.level == 16)
        #expect(events == [.levelledUp(to: 16), .evolves(from: 4, to: 5)])
    }

    @Test func finalStageNeverEvolves() {
        let (_, events) = XPRules.award(10_000, to: Progress(speciesId: 6, level: 40, xp: 0), species: finalStage)
        #expect(!events.contains { if case .evolves = $0 { true } else { false } })
    }

    @Test func levelCapsAtMax() {
        let (next, _) = XPRules.award(10_000_000, to: .starter(6), species: finalStage)
        #expect(next.level == XPRules.maxLevel)
        #expect(next.xp == 0)
    }

    @Test func negativeAwardIsIgnored() {
        let (next, events) = XPRules.award(-50, to: .starter(4), species: stageOne)
        #expect(next == .starter(4))
        #expect(events.isEmpty)
    }

    @Test func sessionXPScalesWithLength() {
        #expect(XPRules.xp(forCompletedSessionOf: 25) == 100)
        #expect(XPRules.xp(forCompletedSessionOf: 50) == 200)
        #expect(XPRules.xp(forCompletedSessionOf: 0) == 0)
    }
}

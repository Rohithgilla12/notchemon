import Foundation
import Testing
@testable import Notchemon

struct StatsReducerTests {
    @Test func foldsALedgerOfEveryKindOfEvent() {
        let ledger: [CompanionEvent] = [
            .walked(points: 100, perch: .topEdge),
            .walked(points: 40, perch: .dock),
            .walked(points: 60, perch: .topEdge),
            .hopped, .hopped,
            .napped,
            .transferred(to: .dock),
            .transferred(to: .topEdge),
            .focusCompleted(minutes: 25),
            .focusCompleted(minutes: 45),
            .evolved,
            .encounterSeen, .encounterSeen,
            .encounterCaught,
        ]
        let stats = ledger.reduce(Stats()) { StatsReducer.apply($1, to: $0) }
        #expect(stats == Stats(
            topEdgePoints: 160, dockPoints: 40, hops: 2, naps: 1, dockVisits: 1, focusSessions: 2, focusMinutes: 70,
            evolutions: 1, encountersSeen: 2, encountersCaught: 1
        ))
    }

    @Test func aWalkAddsBothFunDistancesAtItsOwnScale() {
        let scale = WalkScale(creatureMetresPerPoint: 0.01, screenMillimetresPerPoint: 0.2)
        let stats = StatsReducer.apply(.walked(points: 250, perch: .dock), to: Stats(), scale: scale)
        #expect(stats.dockPoints == 250)
        #expect(abs(stats.creatureMetres - 2.5) < 1e-9)
        #expect(abs(stats.screenMillimetres - 50) < 1e-9)
    }

    @Test func aBackwardWalkNeverSubtracts() {
        let stats = StatsReducer.apply(.walked(points: -30, perch: .topEdge), to: Stats(topEdgePoints: 10))
        #expect(stats.topEdgePoints == 10)
    }

    @Test func statsFromAnOlderFileKeepWhatTheyHave() throws {
        let decoded = try JSONDecoder().decode(Stats.self, from: Data(#"{"hops": 4, "focusMinutes": 50}"#.utf8))
        #expect(decoded == Stats(hops: 4, focusMinutes: 50))
    }
}

struct DistanceTests {
    @Test func theCreatureIsDrawnFortyPointsTall() {
        #expect(Distance.drawnHeight == 40)
    }

    @Test func aFortyCentimetreCreatureDrawnFortyPointsTallWalksACentimetrePerPoint() {
        #expect(abs(Distance.creatureMetresPerPoint(heightMetres: 0.4, drawnHeight: 40) - 0.01) < 1e-12)
    }

    @Test func anUnknownHeightIsAssumed() {
        #expect(Distance.creatureMetresPerPoint(heightMetres: nil, drawnHeight: 40) == Distance.assumedHeightMetres / 40)
    }

    @Test func screenMillimetresComeFromThePhysicalWidthAcrossThePointWidth() {
        let perPoint = Distance.screenMillimetresPerPoint(physicalWidth: 302.4, widthInPoints: 1512)
        #expect(abs(perPoint - 0.2) < 1e-12)
    }

    @Test func aDisplayWithNoPhysicalSizeMeasuresNothing() {
        #expect(Distance.screenMillimetresPerPoint(physicalWidth: 0, widthInPoints: 1512) == 0)
    }
}

struct StatsSummaryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func linesReadAsTheMenuShowsThem() {
        let stats = Stats(
            creatureMetres: 1234, screenMillimetres: 34_500, hops: 128, naps: 12, dockVisits: 9, focusSessions: 14,
            focusMinutes: 360, evolutions: 1, firstMet: now - 3.5 * 86_400
        )
        #expect(StatsSummary.lines(stats, now: now) == [
            "Walked 1.2 km (creature-scale)",
            "34 m on screen",
            "128 hops · 12 naps",
            "9 Dock trips",
            "6 h focus in 14 sessions",
            "1 evolution",
            "Together 3 days",
        ])
    }

    @Test func aNewCompanionReadsInSmallUnits() {
        let stats = Stats(creatureMetres: 0.42, screenMillimetres: 120, hops: 1, naps: 0, dockVisits: 1, focusSessions: 1, focusMinutes: 25, firstMet: now)
        #expect(StatsSummary.lines(stats, now: now) == [
            "Walked 42 cm (creature-scale)",
            "12 cm on screen",
            "1 hop · 0 naps",
            "1 Dock trip",
            "25 min focus in 1 session",
            "Together since today",
        ])
    }

    @Test(arguments: [(90, "1.5 h"), (60, "1 h"), (600, "10 h"), (615, "10 h")])
    func focusTime(minutes: Int, shown: String) {
        #expect(StatsSummary.focus(minutes) == shown)
    }
}

struct RoamEventTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    var walk: RoamWalk { RoamWalk(on: .topEdge, from: 0, to: 140, start: start, speed: 35) }

    @Test func aFinishedWalkCountsItsWholeLength() {
        let events = RoamRules.events(from: .walking(walk), to: .resting(at: .topEdge(140), until: walk.end + 5), at: walk.end)
        #expect(events == [.walked(points: 140, perch: .topEdge)])
    }

    @Test func aWalkCutShortCountsOnlyTheGroundCovered() {
        let events = RoamRules.events(from: .walking(walk), to: .home, at: start + 2)
        #expect(events == [.walked(points: 70, perch: .topEdge)])
    }

    @Test func handingTheSameWalkFromReturningToWalkingCountsNothing() {
        #expect(RoamRules.events(from: .returning(walk), to: .walking(walk), at: start + 1).isEmpty)
    }

    @Test func aHopToTheDockCountsOneTripAndNoWalk() {
        let hop = RoamPhase.transferring(from: .topEdge(140), to: .dock(-20), start: start)
        #expect(RoamRules.events(from: .resting(at: .topEdge(140), until: start), to: hop, at: start) == [.transferred(to: .dock)])
    }

    @Test func aWalkThatStartsCountsNothingYet() {
        #expect(RoamRules.events(from: .resting(at: .home, until: start), to: .walking(walk), at: start).isEmpty)
    }
}

struct EngineStatsTests {
    let clock = TestClock()
    let directory = Fixtures.temporaryDirectory()
    var store: StateStore { StateStore(url: directory.appendingPathComponent("state.json")) }

    func engine(idle: IdleClock = IdleClock(), provider: any CreatureProvider = FakeProvider()) -> CreatureEngine {
        CreatureEngine(
            provider: provider,
            store: store,
            notesURL: directory.appendingPathComponent("notes.md"),
            idleSeconds: { idle.seconds },
            now: { [clock] in clock.now },
            sleepAfter: 5
        )
    }

    @Test func choosingAStarterIsWhenTheyFirstMet() async {
        let engine = engine()
        await engine.start()
        await engine.adopt(901)
        #expect(store.load().stats.firstMet == clock.now)
    }

    @Test func aCompanionFromBeforeStatsMetWhenItsStateWasFirstSaved() async throws {
        try store.save(CompanionState(collection: PartnerCollection(only: .starter(901))))
        let made = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.creationDate: made], ofItemAtPath: directory.path)
        try store.save(CompanionState(collection: PartnerCollection(only: .starter(901))))
        await engine().start()
        #expect(store.load().stats.firstMet == made)
    }

    @Test func eventsBeforeAnyCreatureAreNotCounted() async {
        let engine = engine()
        await engine.start()
        await engine.record(.walked(points: 100, perch: .topEdge))
        #expect(await engine.currentSnapshot.stats == Stats())
    }

    @Test func aWalkIsMeasuredInTheCreaturesHeightAndTheScreensMillimetres() async {
        let engine = engine()
        await engine.start()
        await engine.adopt(901)
        await engine.record(.walked(points: 80, perch: .topEdge), screenMillimetresPerPoint: 0.2)
        let stats = store.load().stats
        #expect(stats.topEdgePoints == 80)
        #expect(abs(stats.creatureMetres - 80 * Distance.assumedHeightMetres / Distance.drawnHeight) < 1e-9)
        #expect(abs(stats.screenMillimetres - 16) < 1e-9)
        #expect(await engine.currentSnapshot.stats == stats)
    }

    @Test func focusHopsNapsAndEvolutionsAreCountedWhereTheyHappen() async {
        let idle = IdleClock()
        let engine = engine(idle: idle)
        await engine.start()
        await engine.adopt(901)
        await engine.startFocus()
        clock.advance(25 * 60)
        await engine.stopFocus()
        await engine.cursorNoticed()
        idle.seconds = 6
        await engine.sample()
        await engine.sample()
        idle.seconds = 0
        await engine.sample()
        await engine.award(200 + 240)
        let stats = store.load().stats
        #expect(stats.focusSessions == 1)
        #expect(stats.focusMinutes == 25)
        #expect(stats.hops == 1)
        #expect(stats.naps == 1)
        #expect(stats.evolutions == 2)
    }

    @Test func statsSurviveARelaunch() async {
        let first = engine()
        await first.start()
        await first.adopt(901)
        await first.record(.transferred(to: .dock))
        let second = engine()
        await second.start()
        #expect(await second.currentSnapshot.stats.dockVisits == 1)
    }
}

struct CompanionStateMigrationTests {
    @Test func focusMinutesFromBeforeStatsMoveIntoStats() throws {
        let json = #"{"progress":{"level":5,"speciesId":25,"xp":100},"totalFocusMinutes":75,"stash":[]}"#
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        #expect(state.stats.focusMinutes == 75)
    }

    @Test func savedStatesNoLongerWriteTheOldTally() throws {
        var state = CompanionState(collection: PartnerCollection(only: .starter(25)))
        state.stats.focusMinutes = 75
        let json = try #require(String(data: try JSONEncoder().encode(state), encoding: .utf8))
        #expect(!json.contains("totalFocusMinutes"))
        #expect(try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8)).stats.focusMinutes == 75)
    }
}

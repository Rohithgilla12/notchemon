import CoreGraphics
import Foundation
import Testing
@testable import Notchemon

struct EncounterRulesTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// 2027-01-15 08:00 UTC.
    let morning = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: 86_400) + 8 * 3_600)

    let around = EncounterConditions(secondsSinceInput: 5, sleeping: false, fullScreen: false, focusing: false, hasPartner: true, visiting: false)

    @Test func onlyAnAwakeUnfocusedUserWithAPartnerAndNoVisitorIsActive() {
        #expect(EncounterRules.isActive(around))
        var away = around
        away.secondsSinceInput = EncounterRules.recentInput
        var asleep = around
        asleep.sleeping = true
        var fullScreen = around
        fullScreen.fullScreen = true
        var focusing = around
        focusing.focusing = true
        var alone = around
        alone.hasPartner = false
        var visited = around
        visited.visiting = true
        var lidClosed = around
        lidClosed.systemAsleep = true
        for conditions in [away, asleep, fullScreen, focusing, alone, visited, lidClosed] {
            #expect(!EncounterRules.isActive(conditions))
        }
    }

    @Test func aFreshClockWaitsBetweenFortyFiveAndNinetyMinutes() {
        var rng = SplitMix64(seed: 3)
        for _ in 0..<50 {
            let clock = EncounterRules.fresh(at: morning, calendar: calendar, using: &rng)
            #expect(EncounterRules.cooldown.contains(clock.cooldownLeft))
            #expect(clock.day == calendar.startOfDay(for: morning))
            #expect(clock.visitsToday == 0)
        }
        let fortyFiveToNinetyMinutes: ClosedRange<TimeInterval> = 2_700...5_400
        #expect(EncounterRules.cooldown == fortyFiveToNinetyMinutes)
    }

    @Test func onlyActiveTimeCountsTowardTheNextVisit() {
        let clock = EncounterClock(cooldownLeft: 3_600, day: calendar.startOfDay(for: morning), visitsToday: 0)
        var schedule = EncounterSchedule(clock: clock, activeSince: nil)
        #expect(EncounterRules.deadline(schedule) == nil)
        schedule = EncounterRules.update(schedule, active: true, now: morning, calendar: calendar)
        #expect(EncounterRules.deadline(schedule) == morning + 3_600)
        schedule = EncounterRules.update(schedule, active: false, now: morning + 1_200, calendar: calendar)
        #expect(schedule.clock.cooldownLeft == 2_400)
        #expect(EncounterRules.deadline(schedule) == nil)
        schedule = EncounterRules.update(schedule, active: true, now: morning + 5_000, calendar: calendar)
        #expect(EncounterRules.deadline(schedule) == morning + 7_400)
    }

    @Test func aVisitCountsAndDrawsTheNextCooldown() {
        var rng = SplitMix64(seed: 9)
        let clock = EncounterClock(cooldownLeft: 0, day: calendar.startOfDay(for: morning), visitsToday: 1)
        let after = EncounterRules.visited(EncounterSchedule(clock: clock, activeSince: morning), using: &rng)
        #expect(after.clock.visitsToday == 2)
        #expect(EncounterRules.cooldown.contains(after.clock.cooldownLeft))
        #expect(after.activeSince == nil)
    }

    @Test func fourVisitsSpendTheDayUntilMidnight() {
        let clock = EncounterClock(cooldownLeft: 0, day: calendar.startOfDay(for: morning), visitsToday: EncounterRules.dailyLimit)
        let spent = EncounterRules.update(EncounterSchedule(clock: clock, activeSince: nil), active: true, now: morning, calendar: calendar)
        #expect(EncounterRules.deadline(spent) == nil)
        let tomorrow = EncounterRules.update(spent, active: true, now: morning + 86_400, calendar: calendar)
        #expect(tomorrow.clock.visitsToday == 0)
        #expect(EncounterRules.deadline(tomorrow) == morning + 86_400)
    }

    /// A long day at the desk with short breaks, minute by minute, as the
    /// engine would see it: never more than four visits, each at least 45
    /// active minutes after the last.
    @Test(arguments: [UInt64(1), 2, 3, 42])
    func aWholeDayKeepsTheLimitAndTheCooldown(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        var schedule = EncounterSchedule(clock: EncounterRules.fresh(at: morning, calendar: calendar, using: &rng), activeSince: nil)
        var visits: [Int] = []
        var activeMinutes = 0
        var wasActive = false
        for minute in 0..<(14 * 60) {
            let now = morning + TimeInterval(minute * 60)
            let active = minute % 50 < 45
            if active != wasActive {
                schedule = EncounterRules.update(schedule, active: active, now: now, calendar: calendar)
                wasActive = active
            }
            if let deadline = EncounterRules.deadline(schedule), deadline <= now {
                visits.append(activeMinutes)
                schedule = EncounterRules.visited(EncounterRules.update(schedule, active: false, now: now, calendar: calendar), using: &rng)
                schedule = EncounterRules.update(schedule, active: active, now: now, calendar: calendar)
            }
            if active { activeMinutes += 1 }
        }
        #expect(visits.count == EncounterRules.dailyLimit)
        let gaps: [Int] = zip(visits, visits.dropFirst()).map { (earlier: Int, later: Int) -> Int in later - earlier }
        #expect(gaps.allSatisfy { $0 >= 45 })
    }
}

struct WildVisitTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let span: ClosedRange<Double> = 100...700

    func visit(seed: UInt64 = 5) -> WildVisit {
        var rng = SplitMix64(seed: seed)
        return WildVisit.plan(on: .topEdge, in: span, start: start, using: &rng)
    }

    @Test(arguments: [UInt64(1), 5, 8, 13])
    func aVisitArrivesStrollsForAMinuteAndLeavesFromTheEndOfItsSpan(seed: UInt64) throws {
        let visit = visit(seed: seed)
        guard case .arrive = visit.legs.first?.track, case .leave(let exit, _) = visit.legs.last?.track else {
            Issue.record("expected an arrival first and a departure last, got \(visit.legs)")
            return
        }
        #expect(exit == span.lowerBound || exit == span.upperBound)
        let contiguous: Bool = zip(visit.legs, visit.legs.dropFirst()).allSatisfy { (leg: WildLeg, next: WildLeg) -> Bool in leg.until == next.from }
        #expect(contiguous)
        #expect(visit.end.timeIntervalSince(visit.start) >= EncounterRules.visitLength)
        let leaving = try #require(visit.legs.last)
        #expect(leaving.from.timeIntervalSince(visit.start) < EncounterRules.visitLength + 30)
        for second in stride(from: 0.0, to: visit.end.timeIntervalSince(start), by: 0.5) {
            let x = try #require(visit.x(at: start + second))
            #expect(span.contains(x))
        }
        #expect(visit.x(at: visit.end) == nil)
        #expect(visit.x(at: start - 1) == nil)
        #expect(visit.farthest <= span.upperBound)
    }

    @Test func theSameSeedPlansTheSameVisit() {
        #expect(visit(seed: 21) == visit(seed: 21))
        #expect(visit(seed: 21) != visit(seed: 22))
    }

    @Test func aCatchEndsTheVisitWhereItStands() throws {
        let visit = visit()
        let now = start + 20
        let x = try #require(visit.x(at: now))
        let caught = try #require(visit.caught(at: now))
        let catchLeg = WildLeg(track: .caught(x, start: now), from: now, until: now + WildVisit.catchLength)
        #expect(caught.legs.last == catchLeg)
        #expect(caught.x(at: now - 1) == visit.x(at: now - 1))
        #expect(caught.end == now + WildVisit.catchLength)
        #expect(visit.caught(at: visit.end + 1) == nil)
    }

    @Test func theSpanKeepsClearOfThePartnerAndHome() throws {
        let range: ClosedRange<Double> = -700...700
        let span = try #require(WildVisit.span(in: range, avoiding: [300, 0], clearance: 88))
        #expect(span == -700...(-88))
        let right = try #require(WildVisit.span(in: range, avoiding: [-300, 0], clearance: 88))
        #expect(right == 88...700)
    }

    @Test func aRangeWithNoRoomForAStrideHasNoSpan() {
        #expect(WildVisit.span(in: -100...100, avoiding: [0], clearance: 88) == nil)
    }
}

struct HoverPolicyWildTests {
    let layout = NotchGeometry.layout(
        for: ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), safeAreaTop: 32, auxiliaryTopLeftWidth: 764, auxiliaryTopRightWidth: 764),
        virtualNotchEnabled: false,
        wander: .topEdge
    )!
    var metrics: PanelMetrics { PanelMetrics(layout: layout) }

    /// The box `AppDelegate` hit-tests, from the visit's own maths at `now`.
    func box(_ visit: WildVisit, at now: Date) throws -> CGRect {
        let x = try #require(visit.x(at: now))
        return HoverPolicy.wildBox(centre: metrics.spriteCentre(expanded: false, roamX: x, panelFrame: layout.expanded))
    }

    @Test func theVisitorTakesClicksWhereverItWalksAndNothingElseOnTheStripDoes() throws {
        var rng = SplitMix64(seed: 4)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let visit = WildVisit.plan(on: .topEdge, in: 200...780, start: start, using: &rng)
        for second in stride(from: 1.0, to: EncounterRules.visitLength, by: 3) {
            let wild = try box(visit, at: start + second)
            let onIt = CGPoint(x: wild.midX, y: wild.midY)
            #expect(HoverPolicy.react(to: onIt, mode: .collapsed, layout: layout, wild: wild) == HoverDecision(mode: .collapsed, hitTestable: true, collapse: .cancel))
            let beside = CGPoint(x: wild.maxX + 30, y: wild.midY)
            #expect(!layout.collapsed.contains(beside))
            #expect(!HoverPolicy.react(to: beside, mode: .collapsed, layout: layout, wild: wild).hitTestable)
        }
    }

    @Test func theNotchColumnStillOpensWithAVisitorAbout() {
        let wild = HoverPolicy.wildBox(centre: CGPoint(x: 1300, y: 1060))
        let onNotch = CGPoint(x: 864, y: 1100)
        #expect(HoverPolicy.react(to: onNotch, mode: .collapsed, layout: layout, wild: wild).mode == .expanded(.hover))
    }

    @Test func aPressInAnotherAppPassesOverTheVisitor() {
        let wild = HoverPolicy.wildBox(centre: CGPoint(x: 1300, y: 1060))
        #expect(!HoverPolicy.react(to: CGPoint(x: 1300, y: 1060), mode: .collapsed, layout: layout, buttonHeld: true, wild: wild).hitTestable)
    }

    @Test func theBoxIsTheSpritesBox() {
        let box = HoverPolicy.wildBox(centre: CGPoint(x: 100, y: 50))
        let expected = CGRect(x: 78, y: 28, width: 44, height: 44)
        #expect(box == expected)
    }
}

struct VisitorHomingTests {
    let conditions = HomingConditions(
        wander: .topEdgeAndDock, panelOpen: false, sleeping: false, focusing: false, fullScreen: false,
        cursorNearHome: true, hasCreature: true, perch: .topEdge, visitor: true
    )

    @Test func aVisitorHoldsThePartnerWhereItIsEvenForACursorAtHome() {
        #expect(RoamRules.homing(conditions) == .stay)
    }

    @Test func openingThePanelStillBringsItHome() {
        var open = conditions
        open.panelOpen = true
        #expect(RoamRules.homing(open) == .snap)
    }

    @Test func aHopUnderWayIsHeldWhereItLands() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let hop = RoamPhase.transferring(from: .topEdge(200), to: .dock(-40), start: start)
        #expect(hop.heldSpot(at: start) == .dock(-40))
        #expect(RoamPhase.resting(at: .topEdge(200), until: start).heldSpot(at: start) == .topEdge(200))
    }
}

struct EngineEncounterTests {
    let clock = TestClock()
    let directory = Fixtures.temporaryDirectory()
    var store: StateStore { StateStore(url: directory.appendingPathComponent("state.json")) }

    func engine() async -> CreatureEngine {
        let engine = CreatureEngine(
            provider: TieredProvider(),
            store: store,
            notesURL: directory.appendingPathComponent("notes.md"),
            idleSeconds: { 0 },
            now: { [clock] in clock.now }
        )
        await engine.start()
        await engine.adopt(901)
        return engine
    }

    @Test func aVisitorArrivesWithItsOwnWalkAndIsCountedAsSeen() async throws {
        let engine = await engine()
        await engine.spawnEncounterNow()
        let encounter = try #require(await engine.currentSnapshot.encounter)
        #expect([901, 904].contains(encounter.species.id))
        #expect(encounter.show.walk != nil)
        #expect(!encounter.caught)
        #expect(store.load().stats.encountersSeen == 1)
        #expect(store.load().encounterClock?.visitsToday == 0)
    }

    @Test func catchingANewFamilyAddsItAtTheStartingLevelWithoutSendingItOut() async throws {
        let engine = await engine()
        var encounter = try #require(await spawn(engine, until: 904))
        await engine.catchEncounter()
        encounter = try #require(await engine.currentSnapshot.encounter)
        #expect(encounter.caught)
        let saved = store.load()
        #expect(saved.collection.partner(904)?.progress == .starter(904))
        #expect(saved.collection.active == 901)
        #expect(saved.stats.encountersCaught == 1)
        #expect(await engine.currentSnapshot.banner == .caught("Testsolo"))
        await engine.endEncounter(encounter.serial)
        #expect(await engine.currentSnapshot.encounter == nil)
    }

    @Test func aFamilyAlreadyHereIsOnlySeenAgain() async throws {
        let engine = await engine()
        _ = try #require(await spawn(engine, until: 901))
        await engine.catchEncounter()
        let saved = store.load()
        #expect(saved.collection.partners.count == 1)
        #expect(saved.stats.encountersCaught == 0)
        #expect(saved.stats.encountersSeen >= 1)
        #expect(await engine.currentSnapshot.banner == .seenAgain("Testmon"))
    }

    @Test func fullScreenSendsTheVisitorAway() async throws {
        let engine = await engine()
        await engine.spawnEncounterNow()
        #expect(await engine.currentSnapshot.encounter != nil)
        await engine.setFullScreen(true)
        #expect(await engine.currentSnapshot.encounter == nil)
    }

    @Test func noVisitorArrivesWhileTheMacSleeps() async {
        let engine = await engine()
        await engine.setSystemAsleep(true)
        await engine.spawnEncounterNow()
        #expect(await engine.currentSnapshot.encounter == nil)
    }

    @Test func noVisitorComesWithoutAPartner() async {
        let engine = CreatureEngine(provider: TieredProvider(), store: store, notesURL: directory.appendingPathComponent("notes.md"), idleSeconds: { 0 })
        await engine.start()
        await engine.spawnEncounterNow()
        #expect(await engine.currentSnapshot.encounter == nil)
    }

    @Test func aRelaunchKeepsTheEncounterClock() async throws {
        // The first sample with a partner out starts the active stretch, which saves the clock.
        await engine().sample()
        let saved = try #require(store.load().encounterClock)
        #expect(EncounterRules.cooldown.contains(saved.cooldownLeft))
        let again = CreatureEngine(
            provider: TieredProvider(), store: store, notesURL: directory.appendingPathComponent("notes.md"), idleSeconds: { 0 },
            now: { [clock] in clock.now }
        )
        await again.start()
        await again.sample()
        #expect(store.load().encounterClock == saved)
    }

    /// Spawns and sends visitors away until one is `id`.
    private func spawn(_ engine: CreatureEngine, until id: Int) async -> Encounter? {
        for _ in 0..<64 {
            await engine.spawnEncounterNow()
            guard let encounter = await engine.currentSnapshot.encounter else { return nil }
            if encounter.species.id == id { return encounter }
            await engine.endEncounter(encounter.serial)
        }
        return nil
    }
}

@MainActor
struct WildWalkerTests {
    @Test func aVisitPlayedToItsEndIsReportedGoneOnceAndRemembered() {
        var rng = SplitMix64(seed: 6)
        let visit = WildVisit.plan(on: .topEdge, in: 100...600, start: Date() - 3_600, using: &rng)
        let walker = WildWalker()
        var gone: [Int] = []
        walker.onGone = { gone.append($0) }
        walker.begin(visit, serial: 7)
        #expect(gone == [7])
        #expect(walker.finished == 7)
        #expect(walker.visit == nil && walker.track == nil)
    }

    @Test func aCatchSwitchesTheLiveVisitToItsCatchAndOnlyOnce() {
        var rng = SplitMix64(seed: 6)
        let walker = WildWalker()
        walker.begin(WildVisit.plan(on: .topEdge, in: 100...600, start: Date() - 1, using: &rng), serial: 3)
        #expect(!walker.isCaught)
        #expect(walker.catchNow())
        #expect(walker.isCaught)
        #expect(!walker.catchNow())
        walker.end()
    }
}

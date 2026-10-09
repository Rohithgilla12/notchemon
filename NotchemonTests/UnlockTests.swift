import CoreGraphics
import Foundation
import Testing
@testable import Notchemon

struct UnlockRulesTests {
    let tiers = [[1, 4], [10, 11, 12], [20, 21, 22]]

    func stats(minutes: Int = 0, kilometres: Double = 0) -> Stats {
        Stats(creatureMetres: kilometres * 1000, focusMinutes: minutes)
    }

    @Test func tierZeroIsOpenFromTheStart() {
        #expect(UnlockRules.available(stats: Stats(), tiers: tiers, override: false) == [1, 4])
        #expect(UnlockRules.openTiers(stats: Stats(), tierCount: tiers.count, override: false) == 1)
    }

    @Test(arguments: [(250, 0.0), (0, 15.0), (249, 15.0), (250, 14.9)])
    func tierOneOpensOnFocusOrWalkingWhicheverComesFirst(minutes: Int, kilometres: Double) {
        #expect(UnlockRules.available(stats: stats(minutes: minutes, kilometres: kilometres), tiers: tiers, override: false) == [1, 4, 10, 11, 12])
    }

    @Test func justShortOfBothKeepsTierOneClosed() {
        #expect(UnlockRules.available(stats: stats(minutes: 249, kilometres: 14.99), tiers: tiers, override: false) == [1, 4])
    }

    @Test func tiersOpenInOrderAsTheThresholdsClimb() {
        let thresholds = UnlockRules.thresholds
        #expect(zip(thresholds, thresholds.dropFirst()).allSatisfy { $0.focusMinutes < $1.focusMinutes && $0.creatureKilometres < $1.creatureKilometres })
        #expect(thresholds.count == 8)
        #expect(UnlockRules.openTiers(stats: stats(minutes: 600), tierCount: 9, override: false) == 3)
    }

    @Test func theOverrideOpensEveryTierEvenPastTheTable() {
        let many: [[Int]] = (0..<12).map { [$0] }
        #expect(UnlockRules.available(stats: Stats(), tiers: many, override: true) == Array(0..<12))
        #expect(UnlockRules.openTiers(stats: stats(minutes: 100_000), tierCount: 12, override: false) == 9)
    }

    @Test func nextNamesTheLowestClosedTier() {
        #expect(UnlockRules.next(stats: Stats(), tierCount: 9)?.tier == 1)
        #expect(UnlockRules.next(stats: stats(kilometres: 40), tierCount: 9)?.threshold == UnlockRules.thresholds[2])
        #expect(UnlockRules.next(stats: stats(minutes: 100_000), tierCount: 9) == nil)
        #expect(UnlockRules.next(stats: Stats(), tierCount: 1) == nil)
    }
}

struct UnlockOverrideTests {
    let defaults = UserDefaults(suiteName: "NotchemonUnlockTests-\(UUID().uuidString)")!

    @Test func debugBuildsStartUnlockedAndReleaseBuildsDoNot() {
        #expect(UnlockOverride.isOn(defaults: defaults, bundleIdentifier: "com.rohithgilla.Notchemon.debug"))
        #expect(!UnlockOverride.isOn(defaults: defaults, bundleIdentifier: "com.rohithgilla.Notchemon"))
    }

    @Test func aSavedChoiceWinsEitherWay() {
        defaults.set(true, forKey: UnlockOverride.defaultsKey)
        #expect(UnlockOverride.isOn(defaults: defaults, bundleIdentifier: "com.rohithgilla.Notchemon"))
        defaults.set(false, forKey: UnlockOverride.defaultsKey)
        #expect(!UnlockOverride.isOn(defaults: defaults, bundleIdentifier: "com.rohithgilla.Notchemon.debug"))
    }
}

/// `FakeProvider`'s species in two tiers: 901 from the start, 904 later.
struct TieredProvider: CreatureProvider {
    let starterIDs = [901]
    let unlockTiers = [[901], [904]]

    func speciesIndex() async throws -> [SpeciesEntry] {
        FakeProvider().roster.values.map { SpeciesEntry(id: $0.id, name: $0.name.lowercased()) }.sorted { $0.id < $1.id }
    }

    func species(id: Int) async throws -> Species {
        try await FakeProvider().species(id: id)
    }

    func sprite(for species: Species, state: SpriteState, facing: Facing) async throws -> SpriteFrames {
        try await FakeProvider().sprite(for: species, state: state, facing: facing)
    }

    func portrait(for species: Species) async throws -> CGImage {
        FakeProvider.image()
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Bool

    init(_ value: Bool) {
        current = value
    }

    var value: Bool {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

struct EngineUnlockTests {
    let directory = Fixtures.temporaryDirectory()
    var store: StateStore { StateStore(url: directory.appendingPathComponent("state.json")) }

    func engine(override: Flag = Flag(false)) async -> CreatureEngine {
        let engine = CreatureEngine(
            provider: TieredProvider(),
            store: store,
            notesURL: directory.appendingPathComponent("notes.md"),
            idleSeconds: { 0 },
            unlockAll: { override.value }
        )
        await engine.start()
        await engine.adopt(901)
        return engine
    }

    @Test func aClosedTiersSpeciesCannotJoin() async {
        let engine = await engine()
        await engine.adopt(904)
        #expect(store.load().collection.partners.map(\.root) == [901])
        #expect(await engine.partnerOptions().map(\.species.id) == [901])
    }

    @Test func openingATierMakesItsSpeciesChoosableButAddsNobody() async {
        let engine = await engine()
        for _ in 0..<5 { await engine.addFocusHour() }
        #expect(await engine.currentSnapshot.unlocks.openTiers == 2)
        #expect(store.load().collection.partners.count == 1)
        #expect(await engine.partnerOptions().map { $0.partner?.root } == [901, nil])
        await engine.adopt(904)
        #expect(store.load().collection.partners.map(\.root) == [901, 904])
        #expect(store.load().progress == .starter(904))
    }

    @Test func aKilometreAtTheCreaturesScaleCountsTowardTheNextTier() async {
        let engine = await engine()
        await engine.addCreatureKilometre()
        #expect(abs(store.load().stats.creatureMetres - 1_000) < 1e-6)
        let next = await engine.currentSnapshot.unlocks.next
        #expect(next == UnlockRules.thresholds[0])
    }

    @Test func theOverrideLetsAnySpeciesJoinAndSearchesThemAll() async {
        let override = Flag(false)
        let engine = await engine(override: override)
        #expect(await engine.searchOptions("test").isEmpty)
        override.value = true
        await engine.refreshUnlocks()
        #expect(await engine.currentSnapshot.unlocks == UnlockStatus(openTiers: 2, override: true, next: nil))
        let found = await engine.searchOptions("test")
        #expect(found.map(\.species.id) == [901, 902, 903, 904])
        #expect(found.map { $0.partner?.root } == [901, nil, nil, nil])
        #expect(await engine.searchOptions("903").map(\.species.id) == [903])
        await engine.adopt(903)
        #expect(store.load().progress == .starter(903))
    }

    @Test func resettingTheCollectionKeepsTheStats() async {
        let engine = await engine()
        await engine.addFocusHour()
        await engine.resetCollection()
        #expect(store.load().collection == PartnerCollection())
        #expect(store.load().stats.focusMinutes == 60)
        #expect(await engine.currentSnapshot.phase == .choosingStarter(carryOver: nil))
    }

    @MainActor
    @Test func aTierOpeningWhileAPartnerIsOutRaisesTheBanner() async throws {
        let engine = await engine()
        let model = CompanionModel(engine: engine)
        Task { await model.run() }
        for _ in 0..<200 where model.activeSpecies == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!model.newPartnersWaiting)
        for _ in 0..<5 { await engine.addFocusHour() }
        for _ in 0..<200 where !model.newPartnersWaiting {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.newPartnersWaiting)
        model.showPartners()
        #expect(!model.newPartnersWaiting)
    }
}
